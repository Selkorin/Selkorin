'use strict';
const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const QRCode = require('qrcode');
const store = require('./store');
const serverOps = require('./serverOps');
const wg = require('./wg');

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 780,
    minWidth: 1000,
    minHeight: 660,
    backgroundColor: '#0a0a0d',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 22 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
  mainWindow.on('closed', () => (mainWindow = null));
}

// Гарантируем единственный экземпляр
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) { if (mainWindow.isMinimized()) mainWindow.restore(); mainWindow.focus(); }
  });
  app.whenReady().then(() => {
    createWindow();
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  });
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
}

// Единообразная обёртка результата
function ok(data) { return { ok: true, data }; }
function fail(err) { return { ok: false, error: err && err.message ? err.message : String(err) }; }

function logSink(event) {
  return (line) => { try { event.sender.send('log', line); } catch {} };
}

// ---- Профили ----
ipcMain.handle('profiles:list', async () => ok(store.listProfiles()));
ipcMain.handle('profiles:save', async (_e, profile) => { try { return ok(store.saveProfile(profile)); } catch (e) { return fail(e); } });
ipcMain.handle('profiles:remove', async (_e, id) => { try { return ok(store.removeProfile(id)); } catch (e) { return fail(e); } });

// ---- Сервер ----
ipcMain.handle('server:test', async (_e, profile) => { try { return ok(await serverOps.testConnection(profile)); } catch (e) { return fail(e); } });
ipcMain.handle('server:bootstrap', async (event, { profile, opts }) => {
  try {
    const res = await serverOps.bootstrap(profile, opts, logSink(event));
    // сохраняем полученные параметры в профиль
    const merged = store.saveProfile({ ...profile, ...res });
    return ok(merged);
  } catch (e) { return fail(e); }
});
ipcMain.handle('server:clients', async (_e, profile) => { try { return ok(await serverOps.listClients(profile)); } catch (e) { return fail(e); } });
ipcMain.handle('server:addClient', async (_e, { profile, name }) => { try { return ok(await serverOps.addClient(profile, name)); } catch (e) { return fail(e); } });
ipcMain.handle('server:delClient', async (_e, { profile, name }) => { try { return ok(await serverOps.delClient(profile, name)); } catch (e) { return fail(e); } });
ipcMain.handle('server:reality', async (event, { profile, dest }) => { try { return ok(await serverOps.installReality(profile, dest, logSink(event))); } catch (e) { return fail(e); } });

// ---- QR ----
ipcMain.handle('qr', async (_e, text) => {
  try {
    const url = await QRCode.toDataURL(text, { margin: 1, width: 320, color: { dark: '#0a0a0d', light: '#ffffff' } });
    return ok(url);
  } catch (e) { return fail(e); }
});

// ---- Локальный туннель (этот Mac) ----
ipcMain.handle('wg:installed', async () => { try { return ok(await wg.wgInstalled()); } catch (e) { return fail(e); } });
ipcMain.handle('wg:status', async () => { try { return ok(await wg.status()); } catch (e) { return fail(e); } });
ipcMain.handle('wg:save', async (_e, { name, conf }) => { try { return ok(wg.saveTunnel(name, conf)); } catch (e) { return fail(e); } });
ipcMain.handle('wg:up', async (_e, name) => { try { return ok(await wg.up(name)); } catch (e) { return fail(e); } });
ipcMain.handle('wg:down', async (_e, name) => { try { return ok(await wg.down(name)); } catch (e) { return fail(e); } });
ipcMain.handle('wg:remove', async (_e, name) => { try { return ok(wg.removeTunnel(name)); } catch (e) { return fail(e); } });

// ---- Файлы / система ----
ipcMain.handle('file:save', async (_e, { defaultName, content }) => {
  try {
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, { defaultPath: defaultName });
    if (canceled || !filePath) return ok(null);
    fs.writeFileSync(filePath, content, { mode: 0o600 });
    return ok(filePath);
  } catch (e) { return fail(e); }
});
ipcMain.handle('open:external', async (_e, url) => { try { await shell.openExternal(url); return ok(true); } catch (e) { return fail(e); } });
ipcMain.handle('app:version', async () => ok(app.getVersion()));
