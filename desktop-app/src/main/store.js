'use strict';
// Персистентное хранилище настроек (профили серверов, локальные туннели).
// Хранится в userData/selkorin.json с правами 0600.
const { app } = require('electron');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function filePath() {
  return path.join(app.getPath('userData'), 'selkorin.json');
}

const DEFAULT = { profiles: [], tunnels: [], settings: {} };

function load() {
  try {
    const raw = fs.readFileSync(filePath(), 'utf8');
    const data = JSON.parse(raw);
    return { ...DEFAULT, ...data };
  } catch {
    return JSON.parse(JSON.stringify(DEFAULT));
  }
}

function save(data) {
  const dir = path.dirname(filePath());
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(filePath(), JSON.stringify(data, null, 2), { mode: 0o600 });
}

function id() {
  return crypto.randomBytes(8).toString('hex');
}

// ---- Профили серверов ----
function listProfiles() {
  return load().profiles;
}

function saveProfile(profile) {
  const data = load();
  if (profile.id) {
    const i = data.profiles.findIndex((p) => p.id === profile.id);
    if (i >= 0) data.profiles[i] = { ...data.profiles[i], ...profile };
    else data.profiles.push(profile);
  } else {
    profile.id = id();
    data.profiles.push(profile);
  }
  save(data);
  return profile;
}

function removeProfile(profileId) {
  const data = load();
  data.profiles = data.profiles.filter((p) => p.id !== profileId);
  save(data);
  return true;
}

function getProfile(profileId) {
  return load().profiles.find((p) => p.id === profileId) || null;
}

// ---- Локальные туннели (этот Mac) ----
function listTunnels() {
  return load().tunnels;
}

function saveTunnelMeta(meta) {
  const data = load();
  const i = data.tunnels.findIndex((t) => t.name === meta.name);
  if (i >= 0) data.tunnels[i] = { ...data.tunnels[i], ...meta };
  else data.tunnels.push(meta);
  save(data);
  return meta;
}

function removeTunnelMeta(name) {
  const data = load();
  data.tunnels = data.tunnels.filter((t) => t.name !== name);
  save(data);
  return true;
}

function setActiveTunnel(name) {
  const data = load();
  data.tunnels = data.tunnels.map((t) => ({ ...t, active: t.name === name }));
  save(data);
}

function clearActiveTunnel(name) {
  const data = load();
  data.tunnels = data.tunnels.map((t) =>
    t.name === name ? { ...t, active: false } : t
  );
  save(data);
}

module.exports = {
  filePath,
  listProfiles,
  saveProfile,
  removeProfile,
  getProfile,
  listTunnels,
  saveTunnelMeta,
  removeTunnelMeta,
  setActiveTunnel,
  clearActiveTunnel,
};
