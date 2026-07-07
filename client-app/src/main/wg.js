'use strict';
// Управление WireGuard-туннелем на этом Mac через wg-quick.
// Требует wireguard-tools (brew install wireguard-tools).
// Конфиг расшифровывается из хранилища и кладётся во временный файл 0600
// только на время подключения.
const { app } = require('electron');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const BIN_PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin';

function runDir() {
  const d = path.join(app.getPath('userData'), 'run');
  fs.mkdirSync(d, { recursive: true, mode: 0o700 });
  return d;
}
function confPath(name) { return path.join(runDir(), `${name}.conf`); }

function sh(cmd) {
  return new Promise((resolve) => {
    exec(cmd, { env: { ...process.env, PATH: `${BIN_PATH}:${process.env.PATH || ''}` } },
      (err, stdout, stderr) => resolve({ code: err ? (err.code || 1) : 0, stdout, stderr }));
  });
}
function shAdmin(innerCmd) {
  const escaped = innerCmd.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const osa = `do shell script "PATH=${BIN_PATH} ${escaped}" with administrator privileges`;
  const osaEscaped = osa.replace(/'/g, `'\\''`);
  return sh(`osascript -e '${osaEscaped}'`);
}

async function installed() {
  const r = await sh('command -v wg-quick');
  return r.code === 0;
}

// Короткое безопасное имя интерфейса из имени ключа
function ifaceName(name) {
  return 'sk' + String(name).replace(/[^a-zA-Z0-9]/g, '').slice(0, 12).toLowerCase();
}

async function up(name, confText) {
  if (!(await installed())) throw new Error('Не установлен wireguard-tools. Выполни в Терминале: brew install wireguard-tools');
  const iface = ifaceName(name);
  const p = confPath(iface);
  fs.writeFileSync(p, String(confText).trim() + '\n', { mode: 0o600 });
  const r = await shAdmin(`wg-quick up '${p}'`);
  if (r.code !== 0) { try { fs.unlinkSync(p); } catch {} throw new Error((r.stderr || r.stdout || 'wg-quick up ошибка').trim()); }
  return { iface };
}

async function down(name) {
  const iface = ifaceName(name);
  const p = confPath(iface);
  const r = await shAdmin(`wg-quick down '${p}'`);
  try { fs.unlinkSync(p); } catch {}
  if (r.code !== 0) throw new Error((r.stderr || r.stdout || 'wg-quick down ошибка').trim());
  return true;
}

module.exports = { installed, up, down, ifaceName };
