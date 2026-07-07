'use strict';
/* Selkorin — пользовательский клиент. Работает поверх window.selkorin (Electron).
   Вне Electron включается демо-режим только для предпросмотра дизайна. */

const IS_REAL = typeof window !== 'undefined' && !!window.selkorin;
const API = IS_REAL ? window.selkorin : demoAPI();

const state = { status: null, keys: [], conn: { connected: false, keyId: null, kind: null }, busy: false };

const $ = (s, r = document) => r.querySelector(s);
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
async function call(p) { const r = await p; if (!r || r.ok !== true) throw new Error((r && r.error) || 'Ошибка'); return r.data; }
function toast(msg, kind = '') {
  const t = h('div', { class: `toast ${kind}` }, msg);
  $('#toasts').append(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 3600);
}
function openModal(node) { const m = $('#modal'); m.innerHTML = ''; m.append(node); $('#modalBackdrop').hidden = false; }
function closeModal() { $('#modalBackdrop').hidden = true; }
$('#modalBackdrop').addEventListener('click', (e) => { if (e.target.id === 'modalBackdrop') closeModal(); });

// ---------- Экран блокировки ----------
let lockMode = 'unlock'; // 'setup' | 'unlock'
function showLock(mode) {
  lockMode = mode;
  $('#main').hidden = true;
  $('#lock').hidden = false;
  const setup = mode === 'setup';
  $('#lockSub').textContent = setup ? 'придумайте пароль' : 'введите пароль';
  $('#lockPass2').hidden = !setup;
  $('#lockPass').value = ''; $('#lockPass2').value = '';
  $('#lockBtn').textContent = setup ? 'Задать пароль' : 'Разблокировать';
  const bio = !setup && state.status && state.status.settings && state.status.settings.biometric && state.status.biometricSupported;
  $('#bioBtn').hidden = !bio;
  $('#lockErr').textContent = '';
  setTimeout(() => $('#lockPass').focus(), 40);
}
async function showMain() {
  $('#lock').hidden = true;
  $('#main').hidden = false;
  try { $('#ver').textContent = 'v' + (await call(API.version())); } catch {}
  state.conn = await call(API.conn.status()).catch(() => state.conn);
  await loadKeys();
  renderConn();
}
$('#lockBtn').addEventListener('click', submitLock);
$('#lockPass').addEventListener('keydown', (e) => { if (e.key === 'Enter') { if (lockMode === 'setup') $('#lockPass2').focus(); else submitLock(); } });
$('#lockPass2').addEventListener('keydown', (e) => { if (e.key === 'Enter') submitLock(); });
async function submitLock() {
  const pass = $('#lockPass').value;
  const err = $('#lockErr');
  if (lockMode === 'setup') {
    if (pass.length < 4) { err.textContent = 'Минимум 4 символа'; return; }
    if (pass !== $('#lockPass2').value) { err.textContent = 'Пароли не совпадают'; return; }
    try { await call(API.sec.setup(pass)); await refreshStatus(); await showMain(); toast('Пароль установлен', 'ok'); }
    catch (e) { err.textContent = e.message; }
  } else {
    try {
      const okUnlock = await call(API.sec.unlock(pass));
      if (!okUnlock) { err.textContent = 'Неверный пароль'; $('#lockPass').select(); return; }
      await refreshStatus(); await showMain();
    } catch (e) { err.textContent = e.message; }
  }
}
$('#bioBtn').addEventListener('click', async () => {
  try { const okBio = await call(API.sec.biometricUnlock()); if (okBio) { await refreshStatus(); await showMain(); } else $('#lockErr').textContent = 'Не удалось'; }
  catch (e) { $('#lockErr').textContent = e.message; }
});

// ---------- Ключи ----------
async function loadKeys() {
  state.keys = await call(API.keys.list()).catch(() => []);
  renderKeys();
}
function renderKeys() {
  const list = $('#keyList');
  list.innerHTML = '';
  $('#keyEmpty').hidden = state.keys.length > 0;
  for (const k of state.keys) {
    const active = state.conn.connected && state.conn.keyId === k.id;
    list.append(h('div', { class: `key-item ${active ? 'active' : ''}`, onclick: () => selectKey(k) },
      h('span', { class: 'key-dot' }),
      h('div', { class: 'key-body' },
        h('div', { class: 'key-name' }, k.name),
        h('div', { class: 'key-type' }, k.type === 'vless' ? 'VLESS · Reality' : 'WireGuard')),
      h('span', { class: 'badge-type' }, k.type === 'vless' ? 'VLESS' : 'WG'),
      h('button', { class: 'key-menu', onclick: (e) => { e.stopPropagation(); keyMenu(k); } }, '⋯')));
  }
}
function selectKey(k) {
  if (state.conn.connected && state.conn.keyId === k.id) { disconnect(); return; }
  connect(k);
}

$('#addKeyBtn').addEventListener('click', addKeyModal);
function addKeyModal() {
  const name = h('input', { type: 'text', placeholder: 'название (например «Дом», «Amsterdam»)' });
  const secret = h('textarea', { placeholder: 'вставьте vless://… или WireGuard-конфиг ([Interface] …)' });
  const form = h('div', {},
    h('h2', {}, 'Новый ключ'),
    h('div', { class: 'sub' }, 'Вставьте ключ, который выдал администратор. Он сохранится зашифрованным на этом устройстве.'),
    h('div', { class: 'fld' }, h('span', {}, 'Название'), name),
    h('div', { class: 'fld' }, h('span', {}, 'Ключ'), secret),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: closeModal }, 'Отмена'),
      h('button', { class: 'btn primary', onclick: save }, 'Сохранить')));
  async function save() {
    const s = secret.value.trim();
    if (!s) { toast('Вставьте ключ', 'err'); return; }
    try {
      const nm = name.value.trim() || (/^vless/i.test(s) ? 'VLESS' : 'WireGuard');
      await call(API.keys.add(nm, s));
      closeModal(); await loadKeys(); toast('Ключ добавлен', 'ok');
    } catch (e) { toast(e.message, 'err'); }
  }
  openModal(form);
  setTimeout(() => secret.focus(), 40);
}

async function keyMenu(k) {
  let qr = '', secret = '';
  try { secret = await call(API.keys.secret(k.id)); } catch {}
  try { if (secret) qr = await call(API.qr(secret)); } catch {}
  const form = h('div', {},
    h('h2', {}, k.name),
    h('div', { class: 'sub' }, k.type === 'vless' ? 'VLESS · Reality' : 'WireGuard'),
    qr ? h('div', { class: 'qr-wrap' }, h('img', { class: 'qr', src: qr, alt: 'QR' })) : null,
    h('div', { class: 'link-box' }, secret || '(нет данных)'),
    h('div', { class: 'actions' },
      h('button', { class: 'btn danger', onclick: () => removeKey(k) }, 'Удалить'),
      h('button', { class: 'btn', onclick: () => { navigator.clipboard.writeText(secret).then(() => toast('Скопировано', 'ok')); } }, 'Копировать'),
      h('button', { class: 'btn ghost', onclick: closeModal }, 'Закрыть')));
  openModal(form);
}
async function removeKey(k) {
  if (state.conn.connected && state.conn.keyId === k.id) { toast('Сначала отключитесь', 'err'); return; }
  try { await call(API.keys.remove(k.id)); closeModal(); await loadKeys(); toast('Ключ удалён'); }
  catch (e) { toast(e.message, 'err'); }
}

// ---------- Подключение ----------
$('#powerBtn').addEventListener('click', () => {
  if (state.busy) return;
  if (state.conn.connected) disconnect();
  else {
    const active = state.keys.find((k) => k.id === state.conn.keyId) || state.keys[0];
    if (!active) { toast('Сначала добавьте ключ', 'err'); addKeyModal(); return; }
    connect(active);
  }
});
async function connect(k) {
  if (state.busy) return;
  setBusy(true);
  try { state.conn = await call(API.conn.connect(k.id)); toast(`Подключено: ${k.name}`, 'ok'); }
  catch (e) { toast(e.message, 'err'); }
  finally { setBusy(false); renderConn(); renderKeys(); }
}
async function disconnect() {
  if (state.busy) return;
  setBusy(true);
  try { state.conn = await call(API.conn.disconnect()); toast('Отключено'); }
  catch (e) { toast(e.message, 'err'); }
  finally { setBusy(false); renderConn(); renderKeys(); }
}
function setBusy(b) { state.busy = b; $('#powerBtn').classList.toggle('busy', b); }
function renderConn() {
  const on = state.conn.connected;
  const power = $('#powerBtn');
  power.classList.toggle('on', on);
  const st = $('#heroStatus');
  st.textContent = on ? 'Защищено' : 'Отключено';
  st.classList.toggle('on', on);
  const cur = state.keys.find((k) => k.id === state.conn.keyId);
  $('#heroServer').textContent = on && cur ? cur.name : (state.keys.length ? 'нажмите, чтобы подключиться' : 'ключ не выбран');
}

// ---------- Настройки ----------
$('#lockNowBtn').addEventListener('click', async () => { try { await call(API.sec.lock()); } catch {} await refreshStatus(); showLock('unlock'); });
$('#settingsBtn').addEventListener('click', settingsModal);
async function settingsModal() {
  const s = await call(API.settings.get()).catch(() => ({}));
  const supported = state.status && state.status.biometricSupported;
  const bioRow = toggleRow('Вход по Touch ID', supported ? 'Разблокировка отпечатком/лицом.' : 'Не поддерживается на этом Mac.', !!s.biometric, async (on) => {
    if (on) {
      const pw = prompt('Подтвердите пароль для включения Touch ID:');
      if (!pw) return false;
      try { await call(API.sec.enableBiometric(pw)); toast('Touch ID включён', 'ok'); return true; }
      catch (e) { toast(e.message, 'err'); return false; }
    } else { await call(API.sec.disableBiometric()); return true; }
  }, !supported);
  const hideRow = toggleRow('Скрыть приложение', 'Убрать из Dock и переключателя. Вернуть окно: ⌘+⌥+S.', !!s.hideDock, async (on) => {
    await call(API.settings.set({ hideDock: on }));
    if (on) toast('Скрыто. Показать окно: ⌘+⌥+S', 'ok');
    return true;
  });
  const autoSel = h('select', {},
    ...[['0', 'никогда'], ['1', '1 мин'], ['5', '5 мин'], ['15', '15 мин'], ['60', '1 час']]
      .map(([v, t]) => h('option', { value: v, selected: String(s.autoLockMin) === v ? 'selected' : null }, t)));
  autoSel.addEventListener('change', () => call(API.settings.set({ autoLockMin: Number(autoSel.value) })).then(() => toast('Сохранено', 'ok')));

  const form = h('div', {},
    h('h2', {}, 'Настройки'),
    h('div', { class: 'sub' }, 'Защита и приватность. Ключи хранятся зашифрованными на этом Mac.'),
    bioRow, hideRow,
    h('div', { class: 'row-toggle' }, h('div', {}, h('div', { class: 'rt-label' }, 'Автоблокировка'), h('div', { class: 'rt-sub' }, 'Блокировать при бездействии.')), autoSel),
    h('div', { class: 'fld', style: 'margin-top:14px' }, h('span', {}, 'Сменить пароль'),
      h('button', { class: 'btn', onclick: changePassModal }, 'Изменить пароль')),
    h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: closeModal }, 'Закрыть')));
  openModal(form);
}
function toggleRow(label, sub, initial, onToggle, disabled) {
  const sw = h('div', { class: `switch ${initial ? 'on' : ''}` });
  if (!disabled) sw.addEventListener('click', async () => {
    const next = !sw.classList.contains('on');
    const okApply = await onToggle(next);
    if (okApply !== false) sw.classList.toggle('on', next);
  });
  else sw.style.opacity = '0.4';
  return h('div', { class: 'row-toggle' }, h('div', {}, h('div', { class: 'rt-label' }, label), h('div', { class: 'rt-sub' }, sub)), sw);
}
function changePassModal() {
  const oldP = h('input', { type: 'password', placeholder: 'текущий пароль' });
  const n1 = h('input', { type: 'password', placeholder: 'новый пароль' });
  const n2 = h('input', { type: 'password', placeholder: 'повтор нового' });
  const form = h('div', {},
    h('h2', {}, 'Смена пароля'),
    h('div', { class: 'fld' }, h('span', {}, 'Текущий'), oldP),
    h('div', { class: 'fld' }, h('span', {}, 'Новый'), n1),
    h('div', { class: 'fld' }, h('span', {}, 'Повтор'), n2),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: settingsModal }, 'Назад'),
      h('button', { class: 'btn primary', onclick: save }, 'Сменить')));
  async function save() {
    if (n1.value.length < 4) { toast('Минимум 4 символа', 'err'); return; }
    if (n1.value !== n2.value) { toast('Пароли не совпадают', 'err'); return; }
    try { await call(API.sec.changePassword(oldP.value, n1.value)); closeModal(); toast('Пароль изменён', 'ok'); }
    catch (e) { toast(e.message, 'err'); }
  }
  openModal(form);
}

// ---------- init ----------
async function refreshStatus() { state.status = await call(API.sec.status()).catch(() => null); }
if (API.onLocked) API.onLocked(() => { showLock('unlock'); });
async function init() {
  if (!IS_REAL) document.body.append(h('div', { style: 'position:fixed;top:32px;right:10px;z-index:50;font-size:9px;letter-spacing:2px;color:#63636f;border:1px solid rgba(255,255,255,0.11);padding:3px 8px;border-radius:20px' }, 'PREVIEW · DEMO'));
  await refreshStatus();
  const forced = location.hash.slice(1);
  if (forced === 'lock') { showLock('unlock'); return; }
  if (forced === 'setup') { showLock('setup'); return; }
  if (!state.status || !state.status.configured) showLock('setup');
  else if (!state.status.unlocked) showLock('unlock');
  else showMain();
}
init();

// ---------- ДЕМО (только предпросмотр вне Electron) ----------
function demoAPI() {
  const D = { ok: (data) => Promise.resolve({ ok: true, data }) };
  let keys = [
    { id: 'k1', name: 'Amsterdam', type: 'vless', addedAt: Date.now(), active: true },
    { id: 'k2', name: 'Дом (WG)', type: 'wireguard', addedAt: Date.now(), active: false },
  ];
  let conn = { connected: true, keyId: 'k1', kind: 'vless' };
  return {
    sec: {
      status: () => D.ok({ configured: true, unlocked: true, settings: { hideDock: false, autoLockMin: 5, biometric: true }, xrayAvailable: true, wgInstalled: true, biometricSupported: true }),
      setup: () => D.ok(true), unlock: () => D.ok(true), lock: () => D.ok(true),
      changePassword: () => D.ok(true), enableBiometric: () => D.ok(true), disableBiometric: () => D.ok(true), biometricUnlock: () => D.ok(true),
    },
    settings: { get: () => D.ok({ hideDock: false, autoLockMin: 5, biometric: true }), set: () => D.ok({}) },
    keys: {
      list: () => D.ok(keys),
      add: (name, secret) => { const k = { id: 'k' + Date.now(), name, type: /^vless/i.test(secret) ? 'vless' : 'wireguard', addedAt: Date.now() }; keys.push(k); return D.ok(k); },
      remove: (id) => { keys = keys.filter((x) => x.id !== id); return D.ok(true); },
      secret: (id) => D.ok(id === 'k1' ? 'vless://11111111-2222-3333-4444-555555555555@203.0.113.45:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=demoPbk&sid=ab12cd34&type=tcp&flow=xtls-rprx-vision#Amsterdam' : '[Interface]\nPrivateKey = demo\nAddress = 10.66.66.9/24'),
    },
    conn: {
      status: () => D.ok(conn),
      connect: (id) => { conn = { connected: true, keyId: id, kind: keys.find((k) => k.id === id).type }; return D.ok(conn); },
      disconnect: () => { conn = { connected: false, keyId: null, kind: null }; return D.ok(conn); },
    },
    qr: () => D.ok(''), openExternal: () => D.ok(true), version: () => D.ok('1.0.0'),
    onLocked: () => () => {},
  };
}
