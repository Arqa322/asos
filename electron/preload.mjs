import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('pulseDesktop', {
  getAppInfo: () => ipcRenderer.invoke('desktop:get-app-info'),
  notify: (title, body) => ipcRenderer.invoke('desktop:notify', title, body),
  toggleWindow: () => ipcRenderer.invoke('desktop:toggle-window'),
  getScreenSources: () => ipcRenderer.invoke('desktop:get-screen-sources'),
});
