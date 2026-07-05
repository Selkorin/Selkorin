'use strict';
/* Selkorin VPN — логика интерфейса рендерера.
   Работает поверх безопасного моста window.selkorin (Electron).
   Если открыть файл вне Electron (в браузере) — включается демо-режим
   ТОЛЬКО для предпросмотра дизайна; в собранном приложении он не активен. */

const IS_REAL = typeof window !== 'undefined' && !!window.selkorin;
const API = IS_REAL ? window.selkorin : demoAPI();

const state = {
  profiles: [],
  selectedId: null,
  clients: [],
  wg: { installed: false, activeName: null, tunnels: [] },
};

// ---------- утилиты ----------
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const h = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined && v !== false) e.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null) e.append(kid.nodeType ? kid : document.createTextNode(kid));
  return e;
};

async function call(promise) {
  const res = await promise;
  if (!res || res.ok !== true) throw new Error((res && res.error) || 'Неизвестная ошибка');
  return res.data;
}

function toast(msg, kind = '') {
  const t = h('div', { class: `toast ${kind}` }, msg);
  $('#toasts').append(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 3800);
}

function selectedProfile() {
  return state.profiles.find((p) => p.id === state.selectedId) || null;
}

function fmtBytes(n) {
  if (!n) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(n) / Math.log(1024));
  return `${(n / Math.pow(1024, i)).toFixed(i ? 1 : 0)} ${u[i]}`;
}
function fmtAgo(unix) {
  if (!unix) return 'никогда';
  const s = Math.floor(Date.now() / 1000 - unix);
  if (s < 0) return 'только что';
  if (s < 60) return `${s} с назад`;
  if (s < 3600) return `${Math.floor(s / 60)} мин назад`;
  if (s < 86400) return `${Math.floor(s / 3600)} ч назад`;
  return `${Math.floor(s / 86400)} дн назад`;
}

// ---------- модалка ----------
function openModal(node) {
  const m = $('#modal');
  m.innerHTML = '';
  m.append(node);
  $('#modalBackdrop').hidden = false;
}
function closeModal() { $('#modalBackdrop').hidden = true; }
$('#modalBackdrop').addEventListener('click', (e) => { if (e.target.id === 'modalBackdrop') closeModal(); });

// ---------- консоль ----------
let logUnsub = null;
function showConsole(title) {
  $('#consoleTitle').textContent = title || 'Журнал';
  $('#consoleBody').textContent = '';
  $('#console').hidden = false;
}
function appendConsole(line) {
  const b = $('#consoleBody');
  b.textContent += line;
  b.scrollTop = b.scrollHeight;
}
$('#consoleClose').addEventListener('click', () => ($('#console').hidden = true));

// ---------- навигация ----------
function switchView(name) {
  $$('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.view === name));
  $$('.view').forEach((v) => v.classList.toggle('active', v.dataset.view === name));
  if (name === 'devices') renderDevices();
  if (name === 'thismac') renderThisMac();
  if (name === 'reality') renderRealityProfiles();
}
$('#nav').addEventListener('click', (e) => {
  const b = e.target.closest('.nav-item');
  if (b) switchView(b.dataset.view);
});

// ---------- СЕРВЕРЫ ----------
async function loadProfiles() {
  state.profiles = await call(API.profiles.list());
  if (!state.selectedId && state.profiles[0]) state.selectedId = state.profiles[0].id;
  renderServers();
  updateActiveProfileLabel();
}

function updateActiveProfileLabel() {
  const p = selectedProfile();
  $('#activeProfile').textContent = p ? `● ${p.name}` : 'сервер не выбран';
}

function renderServers() {
  const list = $('#serverList');
  list.innerHTML = '';
  if (state.profiles.length === 0) {
    list.append(h('div', { class: 'empty' },
      h('div', { class: 'empty-ico' }, '◈'),
      h('p', {}, 'Нет серверов. Добавьте свой VPS — приложение развернёт на нём WireGuard.')));
    return;
  }
  for (const p of state.profiles) {
    const selected = p.id === state.selectedId;
    const card = h('div', { class: `card ${selected ? 'selected' : ''}` },
      h('div', { class: 'card-top' },
        h('div', {},
          h('div', { class: 'card-title' }, p.name),
          h('div', { class: 'card-host' }, `${p.username || 'root'}@${p.host}:${p.port || 22}`)),
        selected ? h('span', { class: 'badge live' }, 'выбран') : h('span', { class: 'badge' }, '—')),
      h('div', { class: 'card-meta' },
        h('div', { class: 'row' }, h('span', {}, 'Endpoint'), h('b', {}, p.endpoint || '— не развёрнут —')),
        h('div', { class: 'row' }, h('span', {}, 'Ключ сервера'), h('b', {}, p.serverPub ? p.serverPub.slice(0, 20) + '…' : '—'))),
      h('div', { class: 'card-actions' },
        h('button', { class: 'btn sm', onclick: () => { state.selectedId = p.id; renderServers(); updateActiveProfileLabel(); toast(`Выбран: ${p.name}`); } }, 'Выбрать'),
        h('button', { class: 'btn sm', onclick: () => testProfile(p) }, 'Проверить'),
        h('button', { class: 'btn sm primary', onclick: () => bootstrapProfile(p) }, 'Развернуть VPN'),
        h('button', { class: 'btn sm', onclick: () => editServer(p) }, 'Изм.'),
        h('button', { class: 'btn sm danger', onclick: () => removeProfile(p) }, '✕')));
    list.append(card);
  }
}

async function testProfile(p) {
  toast(`Проверяю ${p.name}…`);
  try {
    const r = await call(API.server.test(p));
    toast(r.ok ? `✓ ${p.name}: соединение есть` : `✕ ${p.name}: нет ответа`, r.ok ? 'ok' : 'err');
  } catch (e) { toast(`Ошибка: ${e.message}`, 'err'); }
}

async function bootstrapProfile(p) {
  const okGo = confirm(`Развернуть усиленный WireGuard на «${p.name}» (${p.host})?\n\nБудут установлены WireGuard, приватный DNS, файрвол и хардненинг. Это займёт 1–3 минуты.`);
  if (!okGo) return;
  showConsole(`Развёртывание · ${p.name}`);
  if (logUnsub) logUnsub();
  logUnsub = API.onLog ? API.onLog(appendConsole) : null;
  try {
    const merged = await call(API.server.bootstrap(p, { wgPort: p.wgPort || 51820 }));
    Object.assign(p, merged);
    await loadProfiles();
    toast(`✓ VPN развёрнут на ${p.name}`, 'ok');
    appendConsole('\n[✓] Готово. Сервер поднят.\n');
  } catch (e) {
    toast(`Ошибка развёртывания: ${e.message}`, 'err');
    appendConsole(`\n[x] ${e.message}\n`);
  } finally { if (logUnsub) { logUnsub(); logUnsub = null; } }
}

async function removeProfile(p) {
  if (!confirm(`Удалить сервер «${p.name}» из приложения? (сам сервер не трогаем)`)) return;
  await call(API.profiles.remove(p.id));
  if (state.selectedId === p.id) state.selectedId = null;
  await loadProfiles();
  toast('Сервер удалён');
}

// ---- форма сервера ----
function serverForm(existing) {
  const p = existing || { name: '', host: '', port: 22, username: 'root', auth: { type: 'key', keyPath: '' } };
  let authType = (p.auth && p.auth.type) || 'key';

  const keyFields = h('div', { class: 'form', style: 'gap:13px' },
    labeledInput('Путь к приватному SSH-ключу', 'keyPath', (p.auth && p.auth.keyPath) || '~/.ssh/id_ed25519'),
    labeledInput('Passphrase ключа (если есть)', 'passphrase', (p.auth && p.auth.passphrase) || '', 'password'));
  const passFields = h('div', { class: 'form', style: 'gap:13px' },
    labeledInput('Пароль SSH', 'password', (p.auth && p.auth.password) || '', 'password'));
  passFields.hidden = authType !== 'password';
  keyFields.hidden = authType !== 'key';

  const seg = h('div', { class: 'seg' },
    h('button', { class: authType === 'key' ? 'on' : '', onclick: () => setAuth('key') }, 'SSH-ключ'),
    h('button', { class: authType === 'password' ? 'on' : '', onclick: () => setAuth('password') }, 'Пароль'));
  function setAuth(t) {
    authType = t;
    $$('.seg button', seg).forEach((b, i) => b.classList.toggle('on', (i === 0) === (t === 'key')));
    keyFields.hidden = t !== 'key';
    passFields.hidden = t !== 'password';
  }

  const form = h('div', {},
    h('h2', {}, existing ? 'Изменить сервер' : 'Новый сервер'),
    h('div', { class: 'sub' }, 'Данные SSH-доступа к вашему VPS. Хранятся только на этом Mac.'),
    h('div', { class: 'form' },
      labeledInput('Название', 'name', p.name, 'text', 'Amsterdam Node'),
      h('div', { class: 'fld-row' },
        labeledInput('Хост / IP', 'host', p.host, 'text', '203.0.113.45'),
        labeledInput('Порт', 'port', p.port || 22, 'text')),
      labeledInput('Пользователь', 'username', p.username || 'root', 'text', 'root'),
      h('label', { class: 'fld' }, h('span', {}, 'Аутентификация'), seg),
      keyFields, passFields),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: closeModal }, 'Отмена'),
      h('button', { class: 'btn primary', onclick: save }, 'Сохранить')));

  async function save() {
    const g = (n) => { const el = $(`[data-fld="${n}"]`, form); return el ? el.value.trim() : ''; };
    const prof = {
      id: p.id,
      name: g('name') || 'Сервер',
      host: g('host'),
      port: Number(g('port')) || 22,
      username: g('username') || 'root',
      wgPort: p.wgPort || 51820,
      scriptsDir: p.scriptsDir,
      endpoint: p.endpoint,
      serverPub: p.serverPub,
      auth: authType === 'key'
        ? { type: 'key', keyPath: g('keyPath'), passphrase: g('passphrase') }
        : { type: 'password', password: g('password') },
    };
    if (!prof.host) { toast('Укажите хост/IP', 'err'); return; }
    const saved = await call(API.profiles.save(prof));
    state.selectedId = saved.id;
    closeModal();
    await loadProfiles();
    toast(existing ? 'Сервер обновлён' : 'Сервер добавлен', 'ok');
  }
  openModal(form);
}
function labeledInput(label, name, value = '', type = 'text', ph = '') {
  return h('label', { class: 'fld' }, h('span', {}, label),
    h('input', { 'data-fld': name, type, value, placeholder: ph }));
}
function editServer(p) { serverForm(p); }
$('#addServerBtn').addEventListener('click', () => serverForm(null));

// ---------- УСТРОЙСТВА ----------
async function renderDevices() {
  const p = selectedProfile();
  const body = $('#devicesBody');
  body.innerHTML = '';
  if (!p) { $('#devicesHint').textContent = 'Выберите сервер на вкладке «Серверы».'; return; }
  $('#devicesHint').innerHTML = `Сервер: <b>${p.name}</b> · <span class="mono">${p.endpoint || p.host}</span>`;
  body.append(rowMsg('Загрузка устройств…'));
  try {
    state.clients = await call(API.server.clients(p));
    body.innerHTML = '';
    if (state.clients.length === 0) { body.append(rowMsg('Пока нет устройств. Нажмите «Добавить устройство».')); return; }
    for (const c of state.clients) {
      body.append(h('tr', {},
        h('td', {}, h('span', { class: `status-dot ${c.online ? 'online' : ''}` })),
        h('td', {}, h('b', {}, c.name)),
        h('td', { class: 'mono' }, (c.allowedIps || '').split(',')[0] || '—'),
        h('td', { class: 'mono' }, fmtAgo(c.lastHandshake)),
        h('td', { class: 'mono' }, `${fmtBytes(c.rx)} / ${fmtBytes(c.tx)}`),
        h('td', {}, h('button', { class: 'btn sm danger', onclick: () => revokeDevice(c.name) }, 'Отозвать'))));
    }
  } catch (e) {
    body.innerHTML = '';
    body.append(rowMsg(`Ошибка: ${e.message}`));
  }
}
function rowMsg(text) {
  return h('tr', {}, h('td', { colspan: 6, style: 'color:var(--muted);text-align:center;padding:26px' }, text));
}

$('#addDeviceBtn').addEventListener('click', () => {
  const p = selectedProfile();
  if (!p) { toast('Сначала выберите сервер', 'err'); switchView('servers'); return; }
  const inp = h('input', { 'data-fld': 'devname', type: 'text', placeholder: 'phone, laptop, macbook…' });
  const form = h('div', {},
    h('h2', {}, 'Новое устройство'),
    h('div', { class: 'sub' }, `Сервер: ${p.name}. Будут созданы ключи и отдельный preshared-ключ.`),
    h('div', { class: 'form' }, h('label', { class: 'fld' }, h('span', {}, 'Имя устройства'), inp)),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: closeModal }, 'Отмена'),
      h('button', { class: 'btn primary', onclick: create }, 'Создать')));
  async function create() {
    const name = inp.value.trim();
    if (!/^[a-zA-Z0-9_-]+$/.test(name)) { toast('Только буквы, цифры, - и _', 'err'); return; }
    openModal(h('div', {}, h('h2', {}, 'Создаю…'), h('div', { class: 'sub' }, h('span', { class: 'spinner' }), ' генерирую ключи на сервере')));
    try {
      const res = await call(API.server.addClient(p, name));
      showDeviceQR(res.name, res.conf);
      renderDevices();
    } catch (e) { toast(`Ошибка: ${e.message}`, 'err'); closeModal(); }
  }
  openModal(form);
  setTimeout(() => inp.focus(), 50);
});

async function showDeviceQR(name, conf) {
  let qr = '';
  try { qr = await call(API.qr(conf)); } catch {}
  const form = h('div', {},
    h('h2', {}, `Устройство «${name}»`),
    h('div', { class: 'sub' }, 'Отсканируйте QR приложением WireGuard на телефоне, или сохраните .conf.'),
    h('div', { class: 'qr-wrap' }, qr ? h('img', { class: 'qr', src: qr, alt: 'QR' }) : h('div', { class: 'hint' }, '(QR недоступен)')),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: closeModal }, 'Закрыть'),
      h('button', { class: 'btn', onclick: () => saveConf(name, conf) }, 'Сохранить .conf'),
      h('button', { class: 'btn primary', onclick: () => addToThisMac(name, conf) }, 'Подключить этот Mac')));
  openModal(form);
}
async function saveConf(name, conf) {
  try { const p = await call(API.saveFile(`${name}.conf`, conf)); if (p) toast(`Сохранено: ${p}`, 'ok'); } catch (e) { toast(e.message, 'err'); }
}
async function addToThisMac(name, conf) {
  try {
    await call(API.wg.save(name, conf));
    closeModal();
    toast(`Туннель «${name}» добавлен в «Этот Mac»`, 'ok');
    switchView('thismac');
  } catch (e) { toast(e.message, 'err'); }
}
async function revokeDevice(name) {
  const p = selectedProfile();
  if (!confirm(`Отозвать доступ устройства «${name}»?`)) return;
  try { await call(API.server.delClient(p, name)); toast(`«${name}» отозвано`, 'ok'); renderDevices(); }
  catch (e) { toast(e.message, 'err'); }
}

// ---------- ЭТОТ MAC ----------
async function renderThisMac() {
  try { state.wg = await call(API.wg.status()); } catch { state.wg = { installed: false, tunnels: [] }; }
  const banner = $('#wgBanner');
  if (!state.wg.installed) {
    banner.hidden = false;
    banner.innerHTML = 'Не найден <code>wireguard-tools</code>. Установите: <code>brew install wireguard-tools</code> — и туннели заработают.';
  } else banner.hidden = true;

  const list = $('#tunnelList');
  list.innerHTML = '';
  const tunnels = state.wg.tunnels || [];
  $('#tunnelEmpty').hidden = tunnels.length > 0;
  for (const t of tunnels) {
    const active = state.wg.activeName === t.name;
    list.append(h('div', { class: `card ${active ? 'selected' : ''}` },
      h('div', { class: 'card-top' },
        h('div', {}, h('div', { class: 'card-title' }, t.name),
          h('div', { class: 'card-host' }, active ? 'подключён' : 'отключён')),
        h('span', { class: `badge ${active ? 'live' : ''}` }, active ? '● ON' : 'OFF')),
      h('div', { class: 'card-actions' },
        active
          ? h('button', { class: 'btn sm danger', onclick: () => tunnelDown(t.name) }, 'Отключить')
          : h('button', { class: 'btn sm primary', onclick: () => tunnelUp(t.name) }, 'Подключить'),
        h('button', { class: 'btn sm danger', onclick: () => tunnelRemove(t.name) }, '✕'))));
  }
  updateTopStatus();
}
async function tunnelUp(name) {
  toast(`Подключаю «${name}»…`);
  try { await call(API.wg.up(name)); toast(`✓ Подключено: ${name}`, 'ok'); renderThisMac(); }
  catch (e) { toast(e.message, 'err'); }
}
async function tunnelDown(name) {
  try { await call(API.wg.down(name)); toast(`Отключено: ${name}`); renderThisMac(); }
  catch (e) { toast(e.message, 'err'); }
}
async function tunnelRemove(name) {
  if (!confirm(`Удалить локальный туннель «${name}»?`)) return;
  try { await call(API.wg.remove(name)); renderThisMac(); } catch (e) { toast(e.message, 'err'); }
}
function updateTopStatus() {
  const on = !!(state.wg && state.wg.activeName);
  $('#topDot').classList.toggle('on', on);
  $('#topStatusText').textContent = on ? `подключён · ${state.wg.activeName}` : 'не подключён';
}

// ---------- REALITY ----------
function renderRealityProfiles() {
  const sel = $('#realityProfile');
  sel.innerHTML = '';
  for (const p of state.profiles) sel.append(h('option', { value: p.id }, `${p.name} (${p.host})`));
  if (state.selectedId) sel.value = state.selectedId;
}
$('#realityInstallBtn').addEventListener('click', async () => {
  const id = $('#realityProfile').value;
  const p = state.profiles.find((x) => x.id === id);
  if (!p) { toast('Нет сервера', 'err'); return; }
  const dest = $('#realityDest').value.trim() || 'www.microsoft.com';
  if (!confirm(`Установить Xray Reality на «${p.name}» с маскировкой под ${dest}?`)) return;
  showConsole(`Reality · ${p.name}`);
  if (logUnsub) logUnsub();
  logUnsub = API.onLog ? API.onLog(appendConsole) : null;
  try {
    const r = await call(API.server.reality(p, dest));
    $('#realityLink').textContent = r.link;
    try { $('#realityQr').src = await call(API.qr(r.link)); } catch {}
    $('#realityResult').hidden = false;
    toast('✓ Reality установлен', 'ok');
  } catch (e) { toast(e.message, 'err'); appendConsole(`\n[x] ${e.message}\n`); }
  finally { if (logUnsub) { logUnsub(); logUnsub = null; } }
});
$('#copyLinkBtn').addEventListener('click', () => {
  navigator.clipboard.writeText($('#realityLink').textContent).then(() => toast('Ссылка скопирована', 'ok'));
});

// ---------- init ----------
async function init() {
  if (!IS_REAL) document.body.append(h('div', { class: 'preview-flag' }, 'PREVIEW · DEMO'));
  try { const v = await call(API.version()); $('#appVer').textContent = 'v' + v; $('#setVer').textContent = v; } catch {}
  await loadProfiles();
  try { state.wg = await call(API.wg.status()); updateTopStatus(); } catch {}
  if (location.hash) switchView(location.hash.slice(1));
}
init();

// ---------- ДЕМО-адаптер (только предпросмотр вне Electron) ----------
function demoAPI() {
  const D = { ok: (data) => Promise.resolve({ ok: true, data }) };
  const profiles = [
    { id: 'a1', name: 'Amsterdam Node', host: '203.0.113.45', port: 22, username: 'root', endpoint: '203.0.113.45:51820', serverPub: 'kZx7Qp2mN8vL5rT9wF3cYbH1', scriptsDir: '/root/.selkorin' },
    { id: 'b2', name: 'Helsinki Edge', host: '198.51.100.12', port: 22, username: 'root', endpoint: '198.51.100.12:51820', serverPub: 'aW9dK4sB7nQ2xE6uP0jR5tM3' },
  ];
  const clients = [
    { name: 'macbook', allowedIps: '10.66.66.2/32', lastHandshake: Math.floor(Date.now() / 1000) - 22, rx: 4823000000, tx: 918000000, online: true },
    { name: 'iphone', allowedIps: '10.66.66.3/32', lastHandshake: Math.floor(Date.now() / 1000) - 140, rx: 1204000000, tx: 233000000, online: true },
    { name: 'ipad', allowedIps: '10.66.66.4/32', lastHandshake: Math.floor(Date.now() / 1000) - 90000, rx: 55000000, tx: 9000000, online: false },
  ];
  return {
    profiles: { list: () => D.ok(profiles), save: (p) => D.ok({ ...p, id: p.id || 'new' }), remove: () => D.ok(true) },
    server: {
      test: () => D.ok({ ok: true, info: 'Linux 6.8 x86_64 · wireguard v1.0' }),
      bootstrap: (p) => D.ok(p), clients: () => D.ok(clients),
      addClient: (p, n) => D.ok({ name: n, conf: '[Interface]\nPrivateKey = demo\nAddress = 10.66.66.9/24' }),
      delClient: () => D.ok(true), reality: () => D.ok({ link: 'vless://demo@203.0.113.45:443?...' }),
    },
    wg: {
      installed: () => D.ok({ installed: true }),
      status: () => D.ok({ installed: true, activeName: 'macbook', tunnels: [{ name: 'macbook', active: true }, { name: 'iphone', active: false }] }),
      save: () => D.ok(true), up: () => D.ok(true), down: () => D.ok(true), remove: () => D.ok(true),
    },
    qr: () => D.ok(''), saveFile: () => D.ok(null), openExternal: () => D.ok(true), version: () => D.ok('1.0.0'),
    onLog: () => () => {},
  };
}
