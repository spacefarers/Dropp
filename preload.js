const { ipcRenderer, contextBridge } = require('electron');

// Expose window control methods to renderer
contextBridge.exposeInMainWorld('electronAPI', {
    showWindow: () => ipcRenderer.send('show-window'),
    hideWindow: () => ipcRenderer.send('hide-window')
});

// Listen for drag events on the document
document.addEventListener('dragover', () => {
    ipcRenderer.send('dragging-file');
});

document.addEventListener('mouseleave', () => {
    ipcRenderer.send('mouse-leave');
});

document.addEventListener('mouseenter', () => {
    ipcRenderer.send('mouse-enter');
});
