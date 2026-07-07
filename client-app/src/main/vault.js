'use strict';
// Защищённое хранилище пользователя Selkorin.
// Всё лежит в userData/selkorin-client.json (0600). Секреты ключей
// (vless-ссылки, WireGuard-конфиги) шифруются AES-256-GCM ключом,
// выведенным из мастер-пароля (scrypt). Без пароля секреты не читаются.
const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function filePath() {
  return path.join(app.getPath('userData'), 'selkorin-client.json');
}

const DEFAULT = {
  version: 1,
  security: null,          // { salt, verifier, decoy? }
  settings: { hideDock: false, autoLockMin: 5, biometric: false },
  keys: [],                // { id, name, type: 'vless'|'wireguard', enc, addedAt }
};

// Сессионный ключ (в памяти, пока приложение разблокировано)
let sessionKey = null;

function load() {
  try {
    const raw = fs.readFileSync(filePath(), 'utf8');
    return { ...DEFAULT, ...JSON.parse(raw) };
  } catch {
    return JSON.parse(JSON.stringify(DEFAULT));
  }
}

function save(data) {
  fs.mkdirSync(path.dirname(filePath()), { recursive: true });
  fs.writeFileSync(filePath(), JSON.stringify(data, null, 2), { mode: 0o600 });
}

function id() { return crypto.randomBytes(8).toString('hex'); }

function deriveKey(password, saltB64) {
  const salt = Buffer.from(saltB64, 'base64');
  return crypto.scryptSync(String(password), salt, 32, { N: 1 << 15, r: 8, p: 1 });
}

function encWith(key, plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(String(plaintext), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return { iv: iv.toString('base64'), ct: ct.toString('base64'), tag: tag.toString('base64') };
}

function decWith(key, enc) {
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(enc.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(enc.tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(enc.ct, 'base64')), decipher.final()]).toString('utf8');
}

// ---- Статус / настройка пароля ----
function isConfigured() { return !!load().security; }
function isUnlocked() { return !!sessionKey; }

function setupPassword(password) {
  if (!password || String(password).length < 4) throw new Error('Пароль минимум 4 символа');
  const data = load();
  const salt = crypto.randomBytes(16).toString('base64');
  const key = deriveKey(password, salt);
  const verifier = encWith(key, 'selkorin-verify');
  data.security = { salt, verifier };
  save(data);
  sessionKey = key;
  return true;
}

function unlock(password) {
  const data = load();
  if (!data.security) throw new Error('Пароль ещё не задан');
  const key = deriveKey(password, data.security.salt);
  try {
    if (decWith(key, data.security.verifier) === 'selkorin-verify') { sessionKey = key; return true; }
  } catch {}
  return false;
}

function lock() { sessionKey = null; }

function changePassword(oldPass, newPass) {
  if (!unlock(oldPass)) throw new Error('Старый пароль неверен');
  const data = load();
  // Перешифровываем все ключи новым паролем
  const secrets = data.keys.map((k) => decWith(sessionKey, k.enc));
  const salt = crypto.randomBytes(16).toString('base64');
  const nk = deriveKey(newPass, salt);
  data.security = { salt, verifier: encWith(nk, 'selkorin-verify') };
  data.keys = data.keys.map((k, i) => ({ ...k, enc: encWith(nk, secrets[i]) }));
  save(data);
  sessionKey = nk;
  return true;
}

function requireUnlocked() { if (!sessionKey) throw new Error('Приложение заблокировано'); }

// ---- Ключи ----
function listKeys() {
  requireUnlocked();
  return load().keys.map((k) => ({ id: k.id, name: k.name, type: k.type, addedAt: k.addedAt, active: !!k.active }));
}

function getSecret(keyId) {
  requireUnlocked();
  const k = load().keys.find((x) => x.id === keyId);
  if (!k) throw new Error('Ключ не найден');
  return decWith(sessionKey, k.enc);
}

function addKey({ name, type, secret }) {
  requireUnlocked();
  const data = load();
  const rec = { id: id(), name: name || 'Ключ', type, enc: encWith(sessionKey, secret), addedAt: Date.now(), active: false };
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
  filePath, isConfigured, isUnlocked, setupPassword, unlock, lock, changePassword,
  listKeys, getSecret, addKey, removeKey, setActiveKey, clearActiveKeys,
  getSettings, setSettings,
};
