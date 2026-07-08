'use strict';
const { contextBridge, ipcRenderer } = require('electron');
const invoke = (channel, payload) => ipcRenderer.invoke(channel, payload);

contextBridge.exposeInMainWorld('selkorin', {
  sec: {
    status: () => invoke('sec:status'),
    setLock: (method, secret) => invoke('sec:setLock', { method, secret }),
    clearLock: () => invoke('sec:clearLock'),
    unlock: (secret) => invoke('sec:unlock', secret),
    lockNow: () => invoke('sec:lockNow'),
    setBiometric: (on) => invoke('sec:setBiometric', on),
    biometricUnlock: () => invoke('sec:biometricUnlock'),
  },
  settings: {
    get: () => invoke('settings:get'),
    set: (patch) => invoke('settings:set', patch),
  },
  keys: {
    list: () => invoke('keys:list'),
    add: (name, secret) => invoke('keys:add', { name, secret }),
    remove: (id) => invoke('keys:remove', id),
    secret: (id) => invoke('keys:secret', id),
  },
  conn: {
    status: () => invoke('conn:status'),
    connect: (id) => invoke('conn:connect', id),
    disconnect: () => invoke('conn:disconnect'),
  },
  qr: (text) => invoke('qr', text),
  openExternal: (url) => invoke('open:external', url),
  version: () => invoke('app:version'),
  clipboard: { read: () => invoke('clipboard:read'), write: (text) => invoke('clipboard:write', text) },
  camera: { requestAccess: () => invoke('camera:requestAccess') },
  onLocked: (cb) => { const h = () => cb(); ipcRenderer.on('locked', h); return () => ipcRenderer.removeListener('locked', h); },
});
