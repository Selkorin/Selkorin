'use strict';
const { app, BrowserWindow, ipcMain, systemPreferences, safeStorage, globalShortcut, shell, Menu, clipboard, session } = require('electron');
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
  if (!mins || !vault.isProtected() || !vault.isUnlocked()) return;
  clearTimeout(lockTimer);
  lockTimer = setTimeout(() => { vault.lockNow(); if (win) win.webContents.send('locked'); }, mins * 60 * 1000);
}
function disarmAutoLock() { clearTimeout(lockTimer); }

function applyDock() {
  try {
    if (vault.getSettings().hideDock) app.dock.hide();
    else app.dock.show();
  } catch {}
}

// Без Edit-меню на macOS Cmd+V/C/X ничего не делают в текстовых полях —
// Chromium доставляет эти shortcuts через акселераторы меню приложения.
function buildMenu() {
  const isMac = process.platform === 'darwin';
  const template = [
    ...(isMac ? [{
      label: app.name,
      submenu: [
        { role: 'about' }, { type: 'separator' },
        { role: 'services' }, { type: 'separator' },
        { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' },
        { role: 'quit' },
      ],
    }] : []),
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => { if (win) { win.show(); win.focus(); } });
  app.whenReady().then(() => {
    buildMenu();
    session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
      callback(permission === 'media'); // нужно для сканера QR (камера)
    });
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

// ---- Безопасность / блокировка (опциональная, включается пользователем) ----
ipcMain.handle('sec:status', async () => ok({
  protected: vault.isProtected(),
  method: vault.getLockMethod(),           // 'none' | 'pin' | 'pattern'
  unlocked: vault.isUnlocked(),
  settings: vault.getSettings(),
  xrayAvailable: xray.isAvailable(),
  wgInstalled: await wg.installed(),
  biometricSupported: (() => { try { return systemPreferences.canPromptTouchID(); } catch { return false; } })(),
}));
// Задать/сменить способ блокировки
ipcMain.handle('sec:setLock', async (_e, { method, secret }) => { try { return ok(vault.setLock(method, secret)); } catch (e) { return fail(e); } });
// Снять защиту вовсе
ipcMain.handle('sec:clearLock', async () => { try { return ok(vault.clearLock()); } catch (e) { return fail(e); } });
// Разблокировать введённым кодом/паттерном
ipcMain.handle('sec:unlock', async (_e, secret) => { try { return ok(vault.verifyLock(secret)); } catch (e) { return fail(e); } });
// Заблокировать сейчас
ipcMain.handle('sec:lockNow', async () => { vault.lockNow(); return ok(true); });
// Биометрия — просто вкл/выкл настройку (шифрование ключей не зависит от неё)
ipcMain.handle('sec:setBiometric', async (_e, on) => {
  try {
    if (on && !systemPreferences.canPromptTouchID()) throw new Error('Touch ID недоступен');
    vault.setSettings({ biometric: !!on });
    return ok(true);
  } catch (e) { return fail(e); }
});
ipcMain.handle('sec:biometricUnlock', async () => {
  try {
    const s = vault.getSettings();
    if (!s.biometric) throw new Error('Биометрия не включена');
    await systemPreferences.promptTouchID('разблокировать Selkorin');
    return ok(vault.unlockBiometric());
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
ipcMain.handle('clipboard:read', async () => { try { return ok(clipboard.readText()); } catch (e) { return fail(e); } });
ipcMain.handle('clipboard:write', async (_e, text) => { try { clipboard.writeText(String(text)); return ok(true); } catch (e) { return fail(e); } });
ipcMain.handle('camera:requestAccess', async () => {
  try {
    if (process.platform !== 'darwin') return ok(true);
    return ok(await systemPreferences.askForMediaAccess('camera'));
  } catch (e) { return fail(e); }
});
