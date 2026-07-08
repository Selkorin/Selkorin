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
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 3800);
}
let modalCleanup = null;
function openModal(node) { const m = $('#modal'); m.innerHTML = ''; m.append(node); $('#modalBackdrop').hidden = false; }
function closeModal() {
  $('#modalBackdrop').hidden = true;
  if (modalCleanup) { const fn = modalCleanup; modalCleanup = null; fn(); }
}
$('#modalBackdrop').addEventListener('click', (e) => { if (e.target.id === 'modalBackdrop') closeModal(); });

// ============================================================
//  ГРАФИЧЕСКИЙ КЛЮЧ (pattern) — переиспользуемый компонент
// ============================================================
function makePattern(host, { onComplete, live = false }) {
  const SIZE = 240, M = 40, GAP = 80, HIT = 30;
  host.innerHTML = '';
  const wrap = h('div', { class: 'pattern' });
  wrap.style.width = wrap.style.height = SIZE + 'px';
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('class', 'pattern-lines'); svg.setAttribute('viewBox', `0 0 ${SIZE} ${SIZE}`);
  const poly = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
  poly.setAttribute('class', 'pattern-poly'); svg.append(poly);
  wrap.append(svg);
  const dots = [];
  for (let i = 0; i < 9; i++) {
    const col = i % 3, row = Math.floor(i / 3);
    const d = h('div', { class: 'pat-dot' });
    d.style.left = (M + col * GAP - 9) + 'px';
    d.style.top = (M + row * GAP - 9) + 'px';
    wrap.append(d); dots.push(d);
  }
  host.append(wrap);
  const center = (i) => ({ x: M + (i % 3) * GAP, y: M + Math.floor(i / 3) * GAP });

  let picking = false, pick = [];
  function dotAt(px, py) {
    for (let i = 0; i < 9; i++) { const c = center(i); if (Math.hypot(px - c.x, py - c.y) < HIT) return i; }
    return null;
  }
  function redraw(cursor) {
    const pts = pick.map((i) => { const c = center(i); return `${c.x},${c.y}`; });
    if (cursor && pick.length) pts.push(`${cursor.x},${cursor.y}`);
    poly.setAttribute('points', pts.join(' '));
    dots.forEach((d, i) => d.classList.toggle('on', pick.includes(i)));
  }
  function relative(ev) {
    const r = wrap.getBoundingClientRect();
    const sx = SIZE / r.width, sy = SIZE / r.height;
    return { x: (ev.clientX - r.left) * sx, y: (ev.clientY - r.top) * sy };
  }
  function add(idx) { if (idx != null && !pick.includes(idx)) { pick.push(idx); redraw(); } }
  function reset() { pick = []; redraw(); }

  wrap.addEventListener('pointerdown', (ev) => {
    ev.preventDefault(); picking = true; pick = [];
    try { wrap.setPointerCapture(ev.pointerId); } catch {}
    const p = relative(ev); add(dotAt(p.x, p.y)); redraw(p);
  });
  wrap.addEventListener('pointermove', (ev) => {
    if (!picking) return;
    const p = relative(ev); add(dotAt(p.x, p.y)); redraw(p);
  });
  const finish = () => {
    if (!picking) return;
    picking = false;
    const seq = pick.join('');
    redraw();
    if (seq.length) { if (live) reset(); onComplete(seq); }
  };
  wrap.addEventListener('pointerup', finish);
  wrap.addEventListener('pointercancel', finish);
  return { reset, flashError: () => { wrap.classList.add('err'); setTimeout(() => wrap.classList.remove('err'), 500); reset(); } };
}

// ============================================================
//  БЛОКИРОВКА (опциональная)
// ============================================================
let pinDigits = [];
function renderPinDots(root = document) {
  root.querySelectorAll('#pinDots .pin-dot, .modal-dots .pin-dot').forEach((d, i) => d.classList.toggle('filled', i < pinDigits.length));
}
function resetPin() { pinDigits = []; document.querySelectorAll('#pinDots .pin-dot').forEach((d) => d.classList.remove('filled')); }

let patternCtl = null;
function showLock(method) {
  $('#main').hidden = true;
  $('#lock').hidden = false;
  $('#lockErr').textContent = '';
  const bioOn = state.status && state.status.settings && state.status.settings.biometric && state.status.biometricSupported;
  $('#lockPin').hidden = method !== 'pin';
  $('#lockPattern').hidden = method !== 'pattern';
  if (method === 'pin') {
    $('#lockSub').textContent = 'введите PIN';
    resetPin();
    $('#bioKey').hidden = !bioOn;
  } else {
    $('#lockSub').textContent = 'нарисуйте ключ';
    $('#patBioKey').hidden = !bioOn;
    patternCtl = makePattern($('#patternHost'), { onComplete: unlockWith });
  }
  if (bioOn) setTimeout(tryBiometric, 350);
}
async function unlockWith(secret) {
  try {
    const okU = await call(API.sec.unlock(secret));
    if (okU) { await refreshStatus(); await showMain(); return; }
    $('#lockErr').textContent = 'Неверно';
    if (state.status.method === 'pattern' && patternCtl) patternCtl.flashError(); else resetPin();
  } catch (e) { $('#lockErr').textContent = e.message; }
}
async function tryBiometric() {
  try { const okB = await call(API.sec.biometricUnlock()); if (okB) { await refreshStatus(); await showMain(); } } catch {}
}
$('#pinpad').addEventListener('click', (e) => {
  const dk = e.target.closest('button[data-k]');
  if (dk) { if (pinDigits.length < 6) { pinDigits.push(dk.dataset.k); renderPinDots(); if (pinDigits.length === 6) setTimeout(() => unlockWith(pinDigits.join('')), 110); } return; }
  if (e.target.closest('#delKey')) { pinDigits.pop(); renderPinDots(); }
});
$('#bioKey').addEventListener('click', tryBiometric);
$('#patBioKey').addEventListener('click', tryBiometric);

async function showMain() {
  $('#lock').hidden = true;
  $('#main').hidden = false;
  try { $('#ver').textContent = 'v' + (await call(API.version())); } catch {}
  $('#lockNowBtn').hidden = !(state.status && state.status.protected);
  state.conn = await call(API.conn.status()).catch(() => state.conn);
  await loadKeys();
  renderConn();
}

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
  const scanBox = h('div', { class: 'scan-box', hidden: true });
  let stream = null, rafId = null;
  function stopScan() {
    if (rafId) cancelAnimationFrame(rafId); rafId = null;
    if (stream) { stream.getTracks().forEach((t) => t.stop()); stream = null; }
    scanBox.hidden = true; scanBox.innerHTML = '';
  }
  async function startScan() {
    if (!('BarcodeDetector' in window)) { toast('Сканирование QR не поддерживается в этой сборке', 'err'); return; }
    try {
      if (API.camera) { const g = await call(API.camera.requestAccess()); if (!g) { toast('Нет доступа к камере (Системные настройки → Конфиденциальность → Камера)', 'err'); return; } }
      const detector = new window.BarcodeDetector({ formats: ['qr_code'] });
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      const video = h('video', { autoplay: true, muted: true, playsinline: true });
      video.srcObject = stream;
      scanBox.innerHTML = ''; scanBox.append(video, h('div', { class: 'scan-hint' }, 'Наведите камеру на QR…'));
      scanBox.hidden = false; modalCleanup = stopScan;
      const tick = async () => {
        if (!stream) return;
        try { const codes = await detector.detect(video); if (codes && codes[0] && codes[0].rawValue) { secret.value = codes[0].rawValue.trim(); stopScan(); toast('QR распознан', 'ok'); return; } } catch {}
        rafId = requestAnimationFrame(tick);
      };
      rafId = requestAnimationFrame(tick);
    } catch (e) { toast('Нет доступа к камере: ' + e.message, 'err'); }
  }
  async function pasteClip() {
    try { const t = await call(API.clipboard.read()); if (!t) { toast('Буфер обмена пуст', 'err'); return; } secret.value = t.trim(); toast('Вставлено из буфера', 'ok'); }
    catch (e) { toast(e.message, 'err'); }
  }
  const form = h('div', {},
    h('h2', {}, 'Добавить ключ'),
    h('div', { class: 'sub' }, 'Вставьте ключ администратора: из буфера, вручную (⌘V) или сканом QR. Сохранится зашифрованным на этом Mac.'),
    h('div', { class: 'row-btns' },
      h('button', { class: 'btn sm', onclick: pasteClip }, '📋 Вставить из буфера'),
      h('button', { class: 'btn sm', onclick: startScan }, '📷 Сканировать QR')),
    scanBox,
    h('div', { class: 'fld' }, h('span', {}, 'Ключ'), secret),
    h('div', { class: 'fld' }, h('span', {}, 'Название (необязательно)'), name),
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
      h('button', { class: 'btn', onclick: () => call(API.clipboard.write(secret)).then(() => toast('Скопировано', 'ok')).catch((e) => toast(e.message, 'err')) }, 'Копировать'),
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
  setBusy(true); setStatusText('Подключение…');
  try { state.conn = await call(API.conn.connect(k.id)); toast(`Подключено: ${k.name}`, 'ok'); }
  catch (e) { toast(e.message, 'err'); state.conn = { connected: false, keyId: null, kind: null }; }
  finally { setBusy(false); renderConn(); renderKeys(); }
}
async function disconnect() {
  if (state.busy) return;
  setBusy(true); setStatusText('Отключение…');
  try { state.conn = await call(API.conn.disconnect()); toast('Отключено'); }
  catch (e) { toast(e.message, 'err'); }
  finally { setBusy(false); renderConn(); renderKeys(); }
}
function setBusy(b) { state.busy = b; $('#powerBtn').classList.toggle('busy', b); $('#powerBtn').disabled = b; }
function setStatusText(t) { $('#heroStatus').textContent = t; }
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
$('#lockNowBtn').addEventListener('click', async () => { try { await call(API.sec.lockNow()); } catch {} await refreshStatus(); showLock(state.status.method); });
$('#settingsBtn').addEventListener('click', settingsModal);

// Мини PIN-ввод внутри модалки (для установки PIN)
function askPinModal(title, onDone) {
  let digits = [];
  const dots = h('div', { class: 'pin-dots modal-dots' }, ...Array.from({ length: 6 }, () => h('span', { class: 'pin-dot' })));
  const upd = () => dots.querySelectorAll('.pin-dot').forEach((d, i) => d.classList.toggle('filled', i < digits.length));
  const pad = h('div', { class: 'pinpad modal-pinpad' });
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].forEach((k) => {
    if (k === '') { pad.append(h('span')); return; }
    pad.append(h('button', { onclick: () => {
      if (k === '⌫') digits.pop(); else if (digits.length < 6) digits.push(k);
      upd();
      if (digits.length >= 4 && k !== '⌫') { /* авто-продолжение по 4+ не делаем — ждём 4..6 и кнопку */ }
    } }, k));
  });
  const form = h('div', {},
    h('h2', {}, title),
    h('div', { class: 'sub' }, 'Минимум 4 цифры'),
    dots, pad,
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: () => onDone(null) }, 'Отмена'),
      h('button', { class: 'btn primary', onclick: () => { if (digits.length < 4) { toast('Минимум 4 цифры', 'err'); return; } onDone(digits.join('')); } }, 'Далее')));
  openModal(form);
}

// Установка графического ключа в модалке
function askPatternModal(title, onDone) {
  const host = h('div', { class: 'pattern-host' });
  const hint = h('div', { class: 'sub', style: 'text-align:center' }, 'Соедините минимум 4 точки');
  let captured = null;
  const ctl = makePattern(host, { onComplete: (seq) => {
    if (seq.length < 4) { toast('Минимум 4 точки', 'err'); ctl.flashError(); return; }
    captured = seq; hint.textContent = 'Готово. Нажмите «Далее».';
  } });
  const form = h('div', {},
    h('h2', {}, title), hint,
    h('div', { style: 'display:flex;justify-content:center' }, host),
    h('div', { class: 'actions' },
      h('button', { class: 'btn ghost', onclick: () => onDone(null) }, 'Отмена'),
      h('button', { class: 'btn primary', onclick: () => { if (!captured) { toast('Нарисуйте ключ', 'err'); return; } onDone(captured); } }, 'Далее')));
  openModal(form);
}

async function setupLockFlow(method) {
  const ask = method === 'pin' ? askPinModal : askPatternModal;
  const label = method === 'pin' ? 'PIN' : 'графический ключ';
  ask(`Придумайте ${label}`, (first) => {
    if (!first) { settingsModal(); return; }
    ask(`Повторите ${label}`, async (second) => {
      if (!second) { settingsModal(); return; }
      if (first !== second) { toast('Не совпадает', 'err'); settingsModal(); return; }
      try { await call(API.sec.setLock(method, first)); await refreshStatus(); toast('Защита включена', 'ok'); }
      catch (e) { toast(e.message, 'err'); }
      settingsModal();
    });
  });
}

async function settingsModal() {
  const st = state.status || {};
  const s = st.settings || {};
  const method = st.method || 'none';
  const supported = st.biometricSupported;

  const methodRow = (val, label, sub) => {
    const activeM = method === val;
    return h('div', { class: `pick-row ${activeM ? 'on' : ''}`, onclick: async () => {
      if (val === method) return;
      if (val === 'none') { await call(API.sec.clearLock()); await refreshStatus(); toast('Защита отключена'); settingsModal(); return; }
      setupLockFlow(val);
    } },
      h('div', {}, h('div', { class: 'rt-label' }, label), h('div', { class: 'rt-sub' }, sub)),
      h('div', { class: 'pick-mark' }, activeM ? '✓' : ''));
  };

  const bioRow = toggleRow('Touch ID', supported ? 'Разблокировка отпечатком/лицом.' : 'Недоступно на этом Mac.', !!s.biometric, async (on) => {
    if (on && method === 'none') { toast('Сначала включите PIN или ключ', 'err'); return false; }
    try { await call(API.sec.setBiometric(on)); await refreshStatus(); return true; }
    catch (e) { toast(e.message, 'err'); return false; }
  }, !supported || method === 'none');

  const hideRow = toggleRow('Скрыть приложение', 'Убрать из Dock. Показать окно: ⌘+⌥+S.', !!s.hideDock, async (on) => {
    await call(API.settings.set({ hideDock: on }));
    if (on) toast('Скрыто. Вернуть окно: ⌘+⌥+S', 'ok');
    return true;
  });

  const autoSel = h('select', {},
    ...[['0', 'никогда'], ['1', '1 мин'], ['5', '5 мин'], ['15', '15 мин'], ['60', '1 час']]
      .map(([v, t]) => h('option', { value: v, selected: String(s.autoLockMin) === v ? 'selected' : null }, t)));
  autoSel.addEventListener('change', () => call(API.settings.set({ autoLockMin: Number(autoSel.value) })).then(() => toast('Сохранено', 'ok')));

  const form = h('div', {},
    h('h2', {}, 'Настройки'),
    h('div', { class: 'section-label' }, 'Защита (по желанию)'),
    h('div', { class: 'sub', style: 'margin-bottom:12px' }, 'Выберите, как запирать приложение. По умолчанию — без защиты.'),
    methodRow('none', 'Без защиты', 'Открывается сразу'),
    methodRow('pin', 'PIN-код', 'Цифровой код 4–6'),
    methodRow('pattern', 'Графический ключ', 'Соедините точки'),
    h('div', { class: 'divider' }),
    bioRow,
    (method !== 'none') ? h('div', { class: 'row-toggle' }, h('div', {}, h('div', { class: 'rt-label' }, 'Автоблокировка'), h('div', { class: 'rt-sub' }, 'Запирать при бездействии.')), autoSel) : null,
    hideRow,
    h('div', { class: 'actions' }, h('button', { class: 'btn ghost', onclick: closeModal }, 'Закрыть')));
  openModal(form);
}
function toggleRow(label, sub, initial, onToggle, disabled) {
  const sw = h('div', { class: `switch ${initial ? 'on' : ''} ${disabled ? 'off' : ''}` });
  if (!disabled) sw.addEventListener('click', async () => {
    const next = !sw.classList.contains('on');
    const okApply = await onToggle(next);
    if (okApply !== false) sw.classList.toggle('on', next);
  });
  return h('div', { class: 'row-toggle' }, h('div', {}, h('div', { class: 'rt-label' }, label), h('div', { class: 'rt-sub' }, sub)), sw);
}

// ---------- init ----------
async function refreshStatus() { state.status = await call(API.sec.status()).catch(() => null); }
if (API.onLocked) API.onLocked(async () => { await refreshStatus(); showLock(state.status.method); });
async function init() {
  if (!IS_REAL) document.body.append(h('div', { style: 'position:fixed;top:32px;right:10px;z-index:50;font-size:9px;letter-spacing:2px;color:#63636f;border:1px solid rgba(255,255,255,0.11);padding:3px 8px;border-radius:20px' }, 'PREVIEW · DEMO'));
  await refreshStatus();
  const forced = location.hash.slice(1);
  if (forced === 'lock-pin') { state.status = { ...(state.status || {}), protected: true, method: 'pin' }; showLock('pin'); return; }
  if (forced === 'lock-pattern') { state.status = { ...(state.status || {}), protected: true, method: 'pattern' }; showLock('pattern'); return; }
  if (forced === 'settings') { await showMain(); settingsModal(); return; }
  if (state.status && state.status.protected && !state.status.unlocked) showLock(state.status.method);
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
  let lock = { method: 'none' };
  const secretFor = (id) => id === 'k1'
    ? 'vless://11111111-2222-3333-4444-555555555555@203.0.113.45:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=demoPbk&sid=ab12cd34&type=tcp&flow=xtls-rprx-vision#Amsterdam'
    : '[Interface]\nPrivateKey = demo\nAddress = 10.66.66.9/24';
  return {
    sec: {
      status: () => D.ok({ protected: lock.method !== 'none', method: lock.method, unlocked: true, settings: { hideDock: false, autoLockMin: 5, biometric: false }, xrayAvailable: true, wgInstalled: true, biometricSupported: true }),
      setLock: (m) => { lock = { method: m }; return D.ok(true); },
      clearLock: () => { lock = { method: 'none' }; return D.ok(true); },
      unlock: () => D.ok(true), lockNow: () => D.ok(true), setBiometric: () => D.ok(true), biometricUnlock: () => D.ok(true),
    },
    settings: { get: () => D.ok({ hideDock: false, autoLockMin: 5, biometric: false }), set: () => D.ok({}) },
    keys: {
      list: () => D.ok(keys),
      add: (name, secret) => { const k = { id: 'k' + Date.now(), name, type: /^vless/i.test(secret) ? 'vless' : 'wireguard', addedAt: Date.now() }; keys.push(k); return D.ok(k); },
      remove: (id) => { keys = keys.filter((x) => x.id !== id); return D.ok(true); },
      secret: (id) => D.ok(secretFor(id)),
    },
    conn: {
      status: () => D.ok(conn),
      connect: (id) => { conn = { connected: true, keyId: id, kind: keys.find((k) => k.id === id).type }; return D.ok(conn); },
      disconnect: () => { conn = { connected: false, keyId: null, kind: null }; return D.ok(conn); },
    },
    qr: () => D.ok(''), openExternal: () => D.ok(true), version: () => D.ok('1.1.0'),
    clipboard: { read: () => D.ok('vless://demo-clip@203.0.113.45:443?security=reality&sni=www.microsoft.com&pbk=x&sid=ab#Clip'), write: () => D.ok(true) },
    camera: { requestAccess: () => D.ok(true) },
    onLocked: () => () => {},
  };
}
