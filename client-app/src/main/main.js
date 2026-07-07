'use strict';
const { app, BrowserWindow, ipcMain, systemPreferences, safeStorage, globalShortcut, shell } = require('electron');
const path = require('path');
const QRCode = require('qrcode');
const vault = require('./vault');
const wg = require('./wg');
const xray = require('./xray');

let win = null;
let conn = { connected: false, keyId: null, kind: null };
let lockTimer = null;

function createWindow() {
  win = new BrowserWindow({
    width: 460, height: 720, minWidth: 400, minHeight: 620,
    backgroundColor: '#0a0a0d', titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 14, y: 18 }, resizable: true, fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true, nodeIntegration: false, spellcheck: false,
    },
  });
  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
  win.on('closed', () => (win = null));
  win.on('blur', armAutoLock);
  win.on('focus', disarmAutoLock);
}

function armAutoLock() {
  const mins = Number(vault.getSettings().autoLockMin || 0);
  if (!mins || !vault.isUnlocked()) return;
  clearTimeout(lockTimer);
  lockTimer = setTimeout(() => { vault.lock(); if (win) win.webContents.send('locked'); }, mins * 60 * 1000);
}
function disarmAutoLock() { clearTimeout(lockTimer); }

function applyDock() {
  try {
    if (vault.getSettings().hideDock) app.dock.hide();
    else app.dock.show();
  } catch {}
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => { if (win) { win.show(); win.focus(); } });
  app.whenReady().then(() => {
    createWindow();
    applyDock();
    // Горячая клавиша, чтобы вернуть окно, когда приложение скрыто из Dock
    try {
      globalShortcut.register('CommandOrControl+Alt+S', () => {
        if (!win) createWindow();
        else { win.show(); win.focus(); }
      });
    } catch {}
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  });
  app.on('will-quit', () => { globalShortcut.unregisterAll(); });
  app.on('window-all-closed', () => { /* остаёмся в статус-режиме на macOS */ });
}

function ok(data) { return { ok: true, data }; }
function fail(e) { return { ok: false, error: e && e.message ? e.message : String(e) }; }

// ---- Безопасность / блокировка ----
ipcMain.handle('sec:status', async () => ok({
  configured: vault.isConfigured(),
  unlocked: vault.isUnlocked(),
  settings: vault.getSettings(),
  xrayAvailable: xray.isAvailable(),
  wgInstalled: await wg.installed(),
  biometricSupported: (() => { try { return systemPreferences.canPromptTouchID(); } catch { return false; } })(),
}));
ipcMain.handle('sec:setup', async (_e, password) => { try { vault.setupPassword(password); return ok(true); } catch (e) { return fail(e); } });
ipcMain.handle('sec:unlock', async (_e, password) => { try { return ok(vault.unlock(password)); } catch (e) { return fail(e); } });
ipcMain.handle('sec:lock', async () => { vault.lock(); return ok(true); });
ipcMain.handle('sec:changePassword', async (_e, { oldPass, newPass }) => { try { return ok(vault.changePassword(oldPass, newPass)); } catch (e) { return fail(e); } });

// Биометрия (Touch ID): пароль хранится в Keychain через safeStorage
ipcMain.handle('sec:enableBiometric', async (_e, password) => {
  try {
    if (!vault.unlock(password)) throw new Error('Пароль неверен');
    if (!safeStorage.isEncryptionAvailable()) throw new Error('Keychain недоступен');
    const blob = safeStorage.encryptString(String(password)).toString('base64');
    vault.setSettings({ biometric: true, bioBlob: blob });
    return ok(true);
  } catch (e) { return fail(e); }
});
ipcMain.handle('sec:disableBiometric', async () => { vault.setSettings({ biometric: false, bioBlob: null }); return ok(true); });
ipcMain.handle('sec:biometricUnlock', async () => {
  try {
    const s = vault.getSettings();
    if (!s.biometric || !s.bioBlob) throw new Error('Биометрия не настроена');
    await systemPreferences.promptTouchID('разблокировать Selkorin');
    const pw = safeStorage.decryptString(Buffer.from(s.bioBlob, 'base64'));
    return ok(vault.unlock(pw));
  } catch (e) { return fail(e); }
});

// ---- Настройки ----
ipcMain.handle('settings:get', async () => ok(vault.getSettings()));
ipcMain.handle('settings:set', async (_e, patch) => { const s = vault.setSettings(patch); applyDock(); return ok(s); });

// ---- Ключи ----
function detectType(secret) {
  const s = String(secret).trim();
  if (/^vless:\/\//i.test(s)) return 'vless';
  if (/\[Interface\]/i.test(s) && /PrivateKey/i.test(s)) return 'wireguard';
  return null;
}
ipcMain.handle('keys:list', async () => { try { return ok(vault.listKeys()); } catch (e) { return fail(e); } });
ipcMain.handle('keys:add', async (_e, { name, secret }) => {
  try {
    const type = detectType(secret);
    if (!type) throw new Error('Не распознан формат. Вставьте vless://… или WireGuard-конфиг [Interface].');
    if (type === 'vless') xray.parseVless(secret); // валидация
    return ok(vault.addKey({ name, type, secret: String(secret).trim() }));
  } catch (e) { return fail(e); }
});
ipcMain.handle('keys:remove', async (_e, id) => { try { return ok(vault.removeKey(id)); } catch (e) { return fail(e); } });
ipcMain.handle('keys:secret', async (_e, id) => { try { return ok(vault.getSecret(id)); } catch (e) { return fail(e); } });

// ---- Подключение ----
ipcMain.handle('conn:status', async () => ok(conn));
ipcMain.handle('conn:connect', async (_e, id) => {
  try {
    if (conn.connected) await disconnect();
    const list = vault.listKeys();
    const meta = list.find((k) => k.id === id);
    if (!meta) throw new Error('Ключ не найден');
    const secret = vault.getSecret(id);
    if (meta.type === 'vless') await xray.start(secret);
    else await wg.up(meta.name, secret);
    vault.setActiveKey(id);
    conn = { connected: true, keyId: id, kind: meta.type };
    return ok(conn);
  } catch (e) { return fail(e); }
});
ipcMain.handle('conn:disconnect', async () => { try { await disconnect(); return ok(conn); } catch (e) { return fail(e); } });

async function disconnect() {
  if (!conn.connected) return;
  const list = vault.listKeys();
  const meta = list.find((k) => k.id === conn.keyId);
  if (conn.kind === 'vless') await xray.stop();
  else if (meta) await wg.down(meta.name);
  vault.clearActiveKeys();
  conn = { connected: false, keyId: null, kind: null };
}

// ---- Разное ----
ipcMain.handle('qr', async (_e, text) => {
  try { return ok(await QRCode.toDataURL(text, { margin: 1, width: 300, color: { dark: '#0a0a0d', light: '#ffffff' } })); }
  catch (e) { return fail(e); }
});
ipcMain.handle('open:external', async (_e, url) => { try { await shell.openExternal(url); return ok(true); } catch (e) { return fail(e); } });
ipcMain.handle('app:version', async () => ok(app.getVersion()));
