const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('alakeia', {
  getVersion: () => ipcRenderer.invoke('get-app-version')
});
