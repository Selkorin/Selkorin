'use strict';
// VLESS + Reality на этом Mac через встроенный Xray-core.
// Xray поднимается как локальный SOCKS-прокси (127.0.0.1:10808), затем
// системный SOCKS-прокси macOS переключается на него — весь трафик идёт
// через Reality. Отключение возвращает системный прокси в исходное состояние.
const { app } = require('electron');
const { spawn, exec } = require('child_process');
const net = require('net');
const fs = require('fs');
const path = require('path');

const SOCKS_HOST = '127.0.0.1';
const SOCKS_PORT = 10808;
const BIN_PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin';

let proc = null;

function runDir() {
  const d = path.join(app.getPath('userData'), 'run');
  fs.mkdirSync(d, { recursive: true, mode: 0o700 });
  return d;
}

// Путь к встроенному бинарнику Xray (упакован per-arch в Resources/xray)
function xrayBin() {
  const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
  const packaged = path.join(process.resourcesPath || '', 'xray', arch, 'xray');
  if (fs.existsSync(packaged)) return packaged;
  const dev = path.join(__dirname, '..', '..', 'resources', 'xray', arch, 'xray');
  if (fs.existsSync(dev)) return dev;
  return null;
}

function isAvailable() { return !!xrayBin(); }

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

// vless://uuid@host:port?params#tag  →  структура
function parseVless(link) {
  const s = String(link).trim();
  if (!/^vless:\/\//i.test(s)) throw new Error('Это не vless://-ссылка');
  const u = new URL(s);
  const q = u.searchParams;
  const host = u.hostname;
  const port = Number(u.port || 443);
  const uuid = decodeURIComponent(u.username);
  if (!uuid || !host) throw new Error('В ссылке нет UUID или адреса сервера');
  return {
    uuid, host, port,
    sni: q.get('sni') || q.get('peer') || host,
    pbk: q.get('pbk') || '',
    sid: q.get('sid') || '',
    fp: q.get('fp') || 'chrome',
    flow: q.get('flow') || 'xtls-rprx-vision',
    security: q.get('security') || 'reality',
    type: q.get('type') || 'tcp',
  };
}

function buildConfig(v) {
  return {
    log: { loglevel: 'warning' },
    inbounds: [{
      listen: SOCKS_HOST, port: SOCKS_PORT, protocol: 'socks',
      settings: { udp: true, auth: 'noauth' },
      sniffing: { enabled: true, destOverride: ['http', 'tls', 'quic'] },
    }],
    outbounds: [{
      protocol: 'vless',
      settings: { vnext: [{ address: v.host, port: v.port, users: [{ id: v.uuid, encryption: 'none', flow: v.flow }] }] },
      streamSettings: {
        network: v.type, security: v.security,
        realitySettings: { serverName: v.sni, fingerprint: v.fp, publicKey: v.pbk, shortId: v.sid, spiderX: '' },
      },
      tag: 'proxy',
    }, { protocol: 'freedom', tag: 'direct' }],
  };
}

// Активные сетевые сервисы (Wi-Fi, Ethernet …)
async function networkServices() {
  const r = await sh('networksetup -listallnetworkservices');
  return r.stdout.split('\n').slice(1)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('*'));
}

async function setSystemProxy(on) {
  const services = await networkServices();
  if (!services.length) return;
  const cmds = [];
  for (const svc of services) {
    const s = svc.replace(/"/g, '\\"');
    if (on) {
      cmds.push(`networksetup -setsocksfirewallproxy "${s}" ${SOCKS_HOST} ${SOCKS_PORT}`);
      cmds.push(`networksetup -setsocksfirewallproxystate "${s}" on`);
    } else {
      cmds.push(`networksetup -setsocksfirewallproxystate "${s}" off`);
    }
  }
  const r = await shAdmin(cmds.join(' && '));
  if (r.code !== 0) throw new Error((r.stderr || r.stdout || 'Не удалось настроить системный прокси').trim());
}

// Реальная проверка туннеля: через локальный SOCKS5 просим xray дотянуться
// до внешнего хоста. Ответ SOCKS 0x00 приходит только когда исходящее
// соединение через Reality реально установлено — это честный тест «а работает ли».
function probeThroughProxy(host, port, timeoutMs = 6000) {
  return new Promise((resolve) => {
    const sock = net.connect(SOCKS_PORT, SOCKS_HOST);
    let stage = 0;
    const finish = (okv) => { try { sock.destroy(); } catch {} resolve(okv); };
    const timer = setTimeout(() => finish(false), timeoutMs);
    sock.on('error', () => { clearTimeout(timer); finish(false); });
    sock.on('connect', () => sock.write(Buffer.from([0x05, 0x01, 0x00]))); // greeting, no-auth
    sock.on('data', (buf) => {
      if (stage === 0) {
        if (buf.length < 2 || buf[1] !== 0x00) { clearTimeout(timer); return finish(false); }
        const hb = Buffer.from(host, 'utf8');
        const req = Buffer.concat([
          Buffer.from([0x05, 0x01, 0x00, 0x03, hb.length]), hb,
          Buffer.from([(port >> 8) & 0xff, port & 0xff]),
        ]);
        stage = 1;
        sock.write(req);
      } else {
        clearTimeout(timer);
        finish(buf.length >= 2 && buf[1] === 0x00); // REP==0x00 → соединение установлено
      }
    });
  });
}

async function start(link) {
  const bin = xrayBin();
  if (!bin) throw new Error('Встроенный движок Xray не найден в этой сборке. Обнови приложение.');
  if (proc) await stop();
  const v = parseVless(link);
  const cfgPath = path.join(runDir(), 'xray.json');
  fs.writeFileSync(cfgPath, JSON.stringify(buildConfig(v), null, 2), { mode: 0o600 });

  let stderrTail = '';
  await new Promise((resolve, reject) => {
    proc = spawn(bin, ['run', '-c', cfgPath], { env: { ...process.env, PATH: BIN_PATH } });
    let settled = false;
    const done = (fn, arg) => { if (!settled) { settled = true; fn(arg); } };
    proc.on('error', (e) => done(reject, e));
    proc.stderr && proc.stderr.on('data', (d) => { stderrTail = (stderrTail + d.toString()).slice(-500); });
    setTimeout(() => { if (proc && proc.exitCode === null) done(resolve); else done(reject, new Error('Xray не запустился')); }, 900);
    proc.on('exit', (code) => { if (!settled) done(reject, new Error('Xray завершился (код ' + code + ')')); proc = null; });
  });

  // Честная проверка: реально ли поднялся туннель до сервера.
  const okTunnel = await probeThroughProxy(v.sni || 'www.microsoft.com', 443);
  if (!okTunnel) {
    await stop();
    throw new Error('Не удалось установить соединение с сервером. Проверьте ключ (UUID, pbk, sid, SNI) или доступность сервера.' + (stderrTail ? `\n${stderrTail.trim()}` : ''));
  }

  try {
    await setSystemProxy(true);
  } catch (e) {
    await stop();
    throw e;
  }
  return true;
}

async function stop() {
  try { await setSystemProxy(false); } catch {}
  if (proc) { try { proc.kill('SIGTERM'); } catch {} proc = null; }
  return true;
}

function isRunning() { return !!proc; }

module.exports = { isAvailable, parseVless, start, stop, isRunning };
