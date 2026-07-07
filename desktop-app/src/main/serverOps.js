'use strict';
// Операции с VPN-сервером по SSH: развёртывание, список/добавление/удаление
// устройств, установка Reality. Реально выполняет скрипты на сервере.
const path = require('path');
const ssh = require('./ssh');

const SCRIPTS = [
  'install-server.sh', 'add-client.sh', 'del-client.sh', 'install-xray-reality.sh',
  'reality-client-add.sh', 'reality-client-list.sh', 'reality-client-del.sh',
];

function scriptsDir() {
  return path.join(__dirname, '..', '..', 'resources', 'scripts');
}

async function remoteDir(conn) {
  const { stdout } = await ssh.exec(conn, 'echo $HOME');
  const home = (stdout || '').trim() || '/root';
  return `${home}/.selkorin`;
}

async function uploadScripts(conn, dir) {
  await ssh.exec(conn, `mkdir -p ${ssh.shellQuote(dir)}`);
  for (const s of SCRIPTS) {
    await ssh.sftpPut(conn, path.join(scriptsDir(), s), `${dir}/${s}`, 0o755);
  }
}

// Проверка соединения + сбор информации о сервере
async function testConnection(profile) {
  const conn = await ssh.connect(profile);
  try {
    const info = await ssh.exec(conn, 'echo SELKORIN_OK; uname -srm; (wg --version 2>/dev/null || echo "wireguard: не установлен")');
    return { ok: info.stdout.includes('SELKORIN_OK'), info: info.stdout.trim() };
  } finally {
    conn.end();
  }
}

// Развернуть сервер WireGuard (усиленная установка). onLog(line) — поток вывода.
async function bootstrap(profile, opts, onLog) {
  const conn = await ssh.connect(profile);
  try {
    const dir = await remoteDir(conn);
    onLog?.(`[*] Загружаю скрипты в ${dir} ...\n`);
    await uploadScripts(conn, dir);
    const env = [];
    if (opts?.wgPort) env.push(`WG_PORT=${Number(opts.wgPort)}`);
    const cmd = `cd ${ssh.shellQuote(dir)} && ${env.join(' ')} bash install-server.sh`;
    onLog?.('[*] Запускаю install-server.sh ...\n');
    const res = await ssh.execStream(conn, ssh.sudo(profile, cmd), onLog);
    if (res.code !== 0) throw new Error(`Установка завершилась с кодом ${res.code}`);
    // Считываем параметры сервера
    const p = await ssh.exec(conn, ssh.sudo(profile, 'cat /etc/wireguard/params.env'));
    const params = parseEnv(p.stdout);
    return {
      scriptsDir: dir,
      serverPub: params.SRV_PUB || '',
      endpoint: params.PUB_IP ? `${params.PUB_IP}:${params.WG_PORT}` : '',
      wgPort: params.WG_PORT || opts?.wgPort || 51820,
    };
  } finally {
    conn.end();
  }
}

// Список устройств: объединяем конфиг сервера и живую статистику wg
async function listClients(profile) {
  const conn = await ssh.connect(profile);
  try {
    const conf = await ssh.exec(conn, ssh.sudo(profile, 'cat /etc/wireguard/wg0.conf 2>/dev/null'));
    const dump = await ssh.exec(conn, ssh.sudo(profile, 'wg show wg0 dump 2>/dev/null'));
    const peers = parseServerConf(conf.stdout);
    const stats = parseWgDump(dump.stdout);
    return peers.map((pr) => {
      const st = stats[pr.publicKey] || {};
      return {
        name: pr.name || '(без имени)',
        publicKey: pr.publicKey,
        allowedIps: pr.allowedIps,
        endpoint: st.endpoint && st.endpoint !== '(none)' ? st.endpoint : null,
        lastHandshake: st.lastHandshake || 0,
        rx: st.rx || 0,
        tx: st.tx || 0,
        online: st.lastHandshake ? Date.now() / 1000 - st.lastHandshake < 180 : false,
      };
    });
  } finally {
    conn.end();
  }
}

// Добавить устройство → вернуть текст его конфигурации
async function addClient(profile, name) {
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) throw new Error('Имя: только буквы, цифры, - и _');
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    await uploadScripts(conn, dir); // гарантируем наличие скриптов
    const run = await ssh.exec(conn, ssh.sudo(profile, `cd ${ssh.shellQuote(dir)} && bash add-client.sh ${ssh.shellQuote(name)}`));
    if (run.code !== 0 && !/создан/.test(run.stdout)) {
      throw new Error((run.stderr || run.stdout || 'Ошибка add-client.sh').trim());
    }
    const conf = await ssh.exec(conn, ssh.sudo(profile, `cat /etc/wireguard/clients/${ssh.shellQuote(name)}.conf`));
    if (!conf.stdout.includes('[Interface]')) throw new Error('Не удалось прочитать конфиг клиента');
    return { name, conf: conf.stdout.trim() };
  } finally {
    conn.end();
  }
}

// Удалить (отозвать) устройство
async function delClient(profile, name) {
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    const run = await ssh.exec(conn, ssh.sudo(profile, `cd ${ssh.shellQuote(dir)} && bash del-client.sh ${ssh.shellQuote(name)}`));
    if (run.code !== 0) throw new Error((run.stderr || run.stdout || 'Ошибка del-client.sh').trim());
    return true;
  } finally {
    conn.end();
  }
}

// Установить Xray VLESS+Reality, вернуть vless-ссылку
async function installReality(profile, dest, onLog) {
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    await uploadScripts(conn, dir);
    const env = dest ? `DEST_SITE=${ssh.shellQuote(dest)}` : '';
    const cmd = `cd ${ssh.shellQuote(dir)} && ${env} bash install-xray-reality.sh`;
    const res = await ssh.execStream(conn, ssh.sudo(profile, cmd), onLog);
    const m = res.output.match(/vless:\/\/\S+/);
    if (!m) throw new Error('Не удалось получить vless-ссылку (см. лог)');
    return { link: m[0] };
  } finally {
    conn.end();
  }
}

// ---- Reality: генератор ключей (много пользователей) ----

function buildVlessLink(uuid, meta, name) {
  const tag = encodeURIComponent(name || 'Reality');
  return `vless://${uuid}@${meta.ip}:${meta.port}?encryption=none&security=reality` +
    `&sni=${meta.sni}&fp=chrome&pbk=${meta.pbk}&sid=${meta.sid}` +
    `&type=tcp&flow=xtls-rprx-vision#${tag}`;
}

// Выдать новый VLESS-ключ пользователю → вернуть { name, link }
async function realityAddClient(profile, name) {
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) throw new Error('Имя: только буквы, цифры, - и _');
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    await uploadScripts(conn, dir);
    const run = await ssh.exec(conn, ssh.sudo(profile, `cd ${ssh.shellQuote(dir)} && bash reality-client-add.sh ${ssh.shellQuote(name)}`));
    const out = `${run.stdout || ''}\n${run.stderr || ''}`;
    if (/SELKORIN_NOTINSTALLED/.test(out)) throw new Error('Сначала установите Reality на этом сервере (кнопка выше).');
    if (/SELKORIN_EXISTS=/.test(out)) throw new Error(`Ключ «${name}» уже существует`);
    const m = out.match(/SELKORIN_LINK=(\S+)/);
    if (!m) throw new Error((run.stderr || run.stdout || 'Не удалось создать ключ').trim());
    return { name, link: m[1] };
  } finally {
    conn.end();
  }
}

// Список выданных ключей + число живых подключений
async function realityListClients(profile) {
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    await uploadScripts(conn, dir);
    const run = await ssh.exec(conn, ssh.sudo(profile, `cd ${ssh.shellQuote(dir)} && bash reality-client-list.sh`));
    const out = run.stdout || '';
    if (/SELKORIN_NOTINSTALLED/.test(out)) return { installed: false, clients: [], online: 0, meta: null };
    let online = 0;
    let meta = null;
    const rows = [];
    for (const line of out.split('\n')) {
      if (line.startsWith('SELKORIN_ONLINE=')) { online = Number(line.slice(16)) || 0; continue; }
      if (line.startsWith('SELKORIN_META=')) {
        const [pbk, sid, sni, port, ip] = line.slice(14).split('|');
        meta = { pbk, sid, sni, port, ip };
        continue;
      }
      const tab = line.indexOf('\t');
      if (tab > -1) {
        const name = line.slice(0, tab).trim();
        const uuid = line.slice(tab + 1).trim();
        if (uuid) rows.push({ name: name || 'default', uuid });
      }
    }
    const clients = rows.map((c) => ({ ...c, link: meta ? buildVlessLink(c.uuid, meta, c.name) : null }));
    return { installed: true, clients, online, meta };
  } finally {
    conn.end();
  }
}

// Отозвать ключ пользователя
async function realityDelClient(profile, name) {
  const conn = await ssh.connect(profile);
  try {
    const dir = profile.scriptsDir || (await remoteDir(conn));
    await uploadScripts(conn, dir);
    const run = await ssh.exec(conn, ssh.sudo(profile, `cd ${ssh.shellQuote(dir)} && bash reality-client-del.sh ${ssh.shellQuote(name)}`));
    if (!/SELKORIN_DELETED=/.test(run.stdout || '')) {
      throw new Error((run.stderr || run.stdout || 'Ошибка отзыва ключа').trim());
    }
    return true;
  } finally {
    conn.end();
  }
}

// ---- парсеры ----
function parseEnv(text) {
  const out = {};
  for (const line of (text || '').split('\n')) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

function parseServerConf(text) {
  const peers = [];
  let pendingName = null;
  let cur = null;
  const flush = () => {
    if (cur && cur.publicKey) peers.push(cur);
    cur = null;
  };
  for (const raw of (text || '').split('\n')) {
    const line = raw.trim();
    const cm = line.match(/^#\s*client:\s*(.+)$/i);
    if (cm) {
      pendingName = cm[1].trim();
      continue;
    }
    if (line === '[Peer]') {
      flush();
      cur = { name: pendingName, publicKey: '', allowedIps: '' };
      pendingName = null;
      continue;
    }
    if (line === '[Interface]') {
      flush();
      continue;
    }
    if (!cur) continue;
    const kv = line.match(/^(\w+)\s*=\s*(.+)$/);
    if (!kv) continue;
    if (kv[1] === 'PublicKey') cur.publicKey = kv[2].trim();
    if (kv[1] === 'AllowedIPs') cur.allowedIps = kv[2].trim();
  }
  flush();
  return peers;
}

function parseWgDump(text) {
  const stats = {};
  const lines = (text || '').split('\n').filter((l) => l.trim());
  // Первая строка — интерфейс сервера, пропускаем
  for (let i = 1; i < lines.length; i++) {
    const f = lines[i].split(/\s+/);
    if (f.length < 8) continue;
    const [publicKey, , endpoint, , latestHandshake, rx, tx] = f;
    stats[publicKey] = {
      endpoint,
      lastHandshake: Number(latestHandshake) || 0,
      rx: Number(rx) || 0,
      tx: Number(tx) || 0,
    };
  }
  return stats;
}

module.exports = {
  testConnection,
  bootstrap,
  listClients,
  addClient,
  delClient,
  installReality,
  realityAddClient,
  realityListClients,
  realityDelClient,
  _parseServerConf: parseServerConf,
  _parseWgDump: parseWgDump,
};
