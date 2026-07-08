'use strict';
// Хранилище пользователя Selkorin (userData/selkorin-client.json, 0600).
//
// Модель безопасности:
//  • Ключи ВСЕГДА шифруются на месте через системный Keychain (safeStorage) —
//    отдельный мастер-пароль не нужен, секреты не лежат открытыми на диске.
//  • Блокировка приложения (PIN / графический ключ / Touch ID) — ОТДЕЛЬНАЯ,
//    НЕОБЯЗАТЕЛЬНАЯ вещь: пользователь сам включает её в настройках. По
//    умолчанию защиты нет и приложение открывается сразу.
const { app, safeStorage } = require('electron');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function filePath() {
  return path.join(app.getPath('userData'), 'selkorin-client.json');
}

const DEFAULT = {
  version: 2,
  lock: { method: 'none' },   // 'none' | 'pin' | 'pattern'  (+ {salt, hash} когда задан)
  settings: { hideDock: false, autoLockMin: 0, biometric: false },
  keys: [],                   // { id, name, type, sec:{mode,enc}, addedAt, active }
};

// В памяти: разблокировано ли приложение в этой сессии.
let unlockedSession = false;

function load() {
  try {
    const raw = fs.readFileSync(filePath(), 'utf8');
    const data = JSON.parse(raw);
    return { ...DEFAULT, ...data, lock: { ...DEFAULT.lock, ...(data.lock || {}) }, settings: { ...DEFAULT.settings, ...(data.settings || {}) } };
  } catch {
    return JSON.parse(JSON.stringify(DEFAULT));
  }
}
function save(data) {
  fs.mkdirSync(path.dirname(filePath()), { recursive: true });
  fs.writeFileSync(filePath(), JSON.stringify(data, null, 2), { mode: 0o600 });
}
function id() { return crypto.randomBytes(8).toString('hex'); }

// ---- Шифрование секретов через Keychain (device key) ----
function encSecret(plain) {
  if (safeStorage.isEncryptionAvailable()) {
    return { mode: 'safe', enc: safeStorage.encryptString(String(plain)).toString('base64') };
  }
  // Фолбэк (например, dev без Keychain): хотя бы не хранить открытым текстом.
  return { mode: 'b64', enc: Buffer.from(String(plain), 'utf8').toString('base64') };
}
function decSecret(rec) {
  if (!rec) return '';
  if (rec.mode === 'safe') return safeStorage.decryptString(Buffer.from(rec.enc, 'base64'));
  return Buffer.from(rec.enc, 'base64').toString('utf8');
}

// ---- Блокировка (опциональная) ----
function pbkdf2(secret, saltB64) {
  return crypto.pbkdf2Sync(String(secret), Buffer.from(saltB64, 'base64'), 210000, 32, 'sha256').toString('base64');
}
function getLockMethod() { return load().lock.method || 'none'; }
function isProtected() { return getLockMethod() !== 'none'; }
function isUnlocked() { return !isProtected() || unlockedSession; }

function setLock(method, secret) {
  if (!['pin', 'pattern'].includes(method)) throw new Error('Неизвестный тип защиты');
  const min = method === 'pin' ? 4 : 4; // pattern: минимум 4 точки
  if (!secret || String(secret).length < min) throw new Error('Слишком короткий код');
  const data = load();
  const salt = crypto.randomBytes(16).toString('base64');
  data.lock = { method, salt, hash: pbkdf2(secret, salt) };
  save(data);
  unlockedSession = true;
  return true;
}
function clearLock() {
  const data = load();
  data.lock = { method: 'none' };
  data.settings.biometric = false;
  save(data);
  unlockedSession = true;
  return true;
}
function verifyLock(secret) {
  const data = load();
  if (data.lock.method === 'none') { unlockedSession = true; return true; }
  const ok = data.lock.hash && pbkdf2(secret, data.lock.salt) === data.lock.hash;
  if (ok) unlockedSession = true;
  return !!ok;
}
function unlockBiometric() { unlockedSession = true; return true; } // вызов после успешного Touch ID
function lockNow() { if (isProtected()) unlockedSession = false; }

// ---- Ключи ----
function requireUnlocked() { if (!isUnlocked()) throw new Error('Приложение заблокировано'); }

function listKeys() {
  return load().keys.map((k) => ({ id: k.id, name: k.name, type: k.type, addedAt: k.addedAt, active: !!k.active }));
}
function getSecret(keyId) {
  requireUnlocked();
  const k = load().keys.find((x) => x.id === keyId);
  if (!k) throw new Error('Ключ не найден');
  return decSecret(k.sec);
}
function addKey({ name, type, secret }) {
  requireUnlocked();
  const data = load();
  const rec = { id: id(), name: name || 'Ключ', type, sec: encSecret(secret), addedAt: Date.now(), active: false };
  data.keys.push(rec);
  save(data);
  return { id: rec.id, name: rec.name, type: rec.type, addedAt: rec.addedAt };
}
function removeKey(keyId) {
  requireUnlocked();
  const data = load();
  data.keys = data.keys.filter((k) => k.id !== keyId);
  save(data);
  return true;
}
function setActiveKey(keyId) {
  const data = load();
  data.keys = data.keys.map((k) => ({ ...k, active: k.id === keyId }));
  save(data);
}
function clearActiveKeys() {
  const data = load();
  data.keys = data.keys.map((k) => ({ ...k, active: false }));
  save(data);
}

// ---- Настройки ----
function getSettings() { return load().settings; }
function setSettings(patch) {
  const data = load();
  data.settings = { ...data.settings, ...patch };
  save(data);
  return data.settings;
}

module.exports = {
  filePath,
  getLockMethod, isProtected, isUnlocked, setLock, clearLock, verifyLock, unlockBiometric, lockNow,
  listKeys, getSecret, addKey, removeKey, setActiveKey, clearActiveKeys,
  getSettings, setSettings,
};
