const { ipcRenderer } = require('electron');

// Listen for drag events on the document

document.addEventListener('dragover', () => {
    console.log('dragging over');
    ipcRenderer.send('dragging-file');
});

document.addEventListener('mouseleave', () => {
    console.log('mouse left');
});

document.addEventListener('mouseenter', () => {
//     check if there is currently a file being dragged
    console.log('mouse entered');
    ipcRenderer.send('mouse-enter');
});