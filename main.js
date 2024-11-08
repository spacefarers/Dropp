const { app, BrowserWindow, ipcMain } = require('electron');
const {join} = require("path");
let mainWindow;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 500,
        height: 500,
        webPreferences: {
            preload: join(__dirname, 'preload.js'),
        },
        transparent: true, // Make the window transparent
        frame: false,      // Remove window frame
        alwaysOnTop: true, // Keep it on top of other windows
        hasShadow: false,  // Optional: remove shadow for cleaner look
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
        },
    });
    // mainWindow.setPosition(screen.getPrimaryDisplay().workAreaSize.width - mainWindow.getBounds().width, (screen.getPrimaryDisplay().workAreaSize.height - mainWindow.getBounds().height) / 2);
    mainWindow.loadFile('index.html');
    // mainWindow.setIgnoreMouseEvents(true, { forward: true });
    // mainWindow.setFocusable(false); // Disable focusing

    // Hide window when it's not focused
    // mainWindow.on('blur', () => {
    //     mainWindow.hide();
    // });
}

app.whenReady().then(() => {
    createWindow();
    console.log('app is ready');
    // Listen for drag events from renderer
    ipcMain.on('dragging-file', (event, isDragging) => {
        console.log('dragging over');
        if (isDragging) {
            mainWindow.show();
        } else {
            // mainWindow.hide();
        }
    });
});

app.on('window-all-closed', () => {
    console.log('all windows closed');
    if (process.platform !== 'darwin') {
        app.quit();
    }
});
