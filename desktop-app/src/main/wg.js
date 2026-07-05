'use strict';
// Управление VPN-туннелем НА САМОМ Mac через wg-quick.
// Требует установленного wireguard-tools (brew install wireguard-tools).
// Привилегированные команды поднимаются через osascript (запрос пароля админа).
const { app } = require('electron');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const store = require('./store');

// Пути Homebrew (Apple Silicon и Intel) + системные
const BIN_PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin';

function tunnelsDir() {
  const d = path.join(app.getPath('userData'), 'tunnels');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function tunnelPath(name) {
  return path.join(tunnelsDir(), `${name}.conf`);
}

function sh(cmd) {
  return new Promise((resolve) => {
    exec(cmd, { env: { ...process.env, PATH: `${BIN_PATH}:${process.env.PATH || ''}` } },
      (err, stdout, stderr) => resolve({ code: err ? (err.code || 1) : 0, stdout, stderr }));
  });
}

// Запуск команды с правами администратора (диалог macOS)
function shAdmin(innerCmd) {
  const escaped = innerCmd.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const osa = `do shell script "PATH=${BIN_PATH} ${escaped}" with administrator privileges`;
  const osaEscaped = osa.replace(/'/g, `'\\''`);
  return sh(`osascript -e '${osaEscaped}'`);
}

// Установлен ли wireguard-tools
async function wgInstalled() {
  const r = await sh('command -v wg-quick');
  return { installed: r.code === 0, path: r.stdout.trim() };
}

// Сохранить конфиг туннеля для этого Mac
function saveTunnel(name, confText) {
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) throw new Error('Имя: только буквы, цифры, - и _');
  const p = tunnelPath(name);
  fs.writeFileSync(p, confText.trim() + '\n', { mode: 0o600 });
  store.saveTunnelMeta({ name, path: p, active: false, addedAt: Date.now() });
  return { name, path: p };
}

function listTunnels() {
  return store.listTunnels();
}

function removeTunnel(name) {
  try { fs.unlinkSync(tunnelPath(name)); } catch {}
  store.removeTunnelMeta(name);
  return true;
}

// Поднять туннель
async function up(name) {
  const p = tunnelPath(name);
  if (!fs.existsSync(p)) throw new Error('Конфиг туннеля не найден');
  const chk = await wgInstalled();
  if (!chk.installed) throw new Error('wireguard-tools не установлен. Выполни: brew install wireguard-tools');
  const r = await shAdmin(`wg-quick up '${p}'`);
  if (r.code !== 0) throw new Error((r.stderr || r.stdout || 'wg-quick up завершился ошибкой').trim());
  store.setActiveTunnel(name);
  return true;
}

// Опустить туннель
async function down(name) {
  const p = tunnelPath(name);
  const r = await shAdmin(`wg-quick down '${p}'`);
  if (r.code !== 0) throw new Error((r.stderr || r.stdout || 'wg-quick down завершился ошибкой').trim());
  store.clearActiveTunnel(name);
  return true;
}

// Статус: какой туннель отмечен активным + проверка наличия wg
async function status() {
  const chk = await wgInstalled();
  const tunnels = store.listTunnels();
  const active = tunnels.find((t) => t.active) || null;
  return { installed: chk.installed, activeName: active ? active.name : null, tunnels };
}

module.exports = { wgInstalled, saveTunnel, listTunnels, removeTunnel, up, down, status, tunnelPath };
