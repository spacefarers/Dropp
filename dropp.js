let filesInDropp = [];

const windowArea = document.getElementById('mainWindow');

windowArea.ondragover = (e) => {
    console.log('dragging over');
    e.preventDefault();
    windowArea.classList.add('dragging');
}