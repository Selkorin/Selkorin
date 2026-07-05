'use strict';
// Безопасный мост между рендерером и главным процессом (contextIsolation).
const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel, payload) => ipcRenderer.invoke(channel, payload);

contextBridge.exposeInMainWorld('selkorin', {
  profiles: {
    list: () => invoke('profiles:list'),
    save: (p) => invoke('profiles:save', p),
    remove: (id) => invoke('profiles:remove', id),
  },
  server: {
    test: (p) => invoke('server:test', p),
    bootstrap: (profile, opts) => invoke('server:bootstrap', { profile, opts }),
    clients: (p) => invoke('server:clients', p),
    addClient: (profile, name) => invoke('server:addClient', { profile, name }),
    delClient: (profile, name) => invoke('server:delClient', { profile, name }),
    reality: (profile, dest) => invoke('server:reality', { profile, dest }),
  },
  wg: {
    installed: () => invoke('wg:installed'),
    status: () => invoke('wg:status'),
    save: (name, conf) => invoke('wg:save', { name, conf }),
    up: (name) => invoke('wg:up', name),
    down: (name) => invoke('wg:down', name),
    remove: (name) => invoke('wg:remove', name),
  },
  qr: (text) => invoke('qr', text),
  saveFile: (defaultName, content) => invoke('file:save', { defaultName, content }),
  openExternal: (url) => invoke('open:external', url),
  version: () => invoke('app:version'),
  onLog: (cb) => {
    const h = (_e, line) => cb(line);
    ipcRenderer.on('log', h);
    return () => ipcRenderer.removeListener('log', h);
  },
});
