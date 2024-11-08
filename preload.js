const { ipcRenderer } = require('electron');

// Listen for drag events on the document
document.addEventListener('dragenter', () => {
    console.log('dragging over');
    ipcRenderer.send('dragging-file', true); // Notify main process that dragging started
});

document.addEventListener('dragleave', () => {
    console.log('dragging left');
    ipcRenderer.send('dragging-file', false); // Notify main process that dragging ended
});
