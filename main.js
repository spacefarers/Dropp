const { app, BrowserWindow, ipcMain, screen } = require('electron');
const {join} = require("path");
let mainWindow;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 200,
        height: 400,
        webPreferences: {
            preload: join(__dirname, 'preload.js'),
        },
        transparent: true, // Make the window transparent
        frame: false,      // Remove window frame
        alwaysOnTop: true, // Keep it on top of other windows
        hasShadow: false,  // Optional: remove shadow for cleaner look
    });
    const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;
    const x = screenWidth - mainWindow.getBounds().width;
    const y = (screenHeight / 2) - (mainWindow.getBounds().height / 2);
    mainWindow.setPosition(x, y);
    // mainWindow.setPosition(screen.getPrimaryDisplay().workAreaSize.width - mainWindow.getBounds().width, (screen.getPrimaryDisplay().workAreaSize.height - mainWindow.getBounds().height) / 2);
    mainWindow.loadFile('index.html');
    mainWindow.setIgnoreMouseEvents(true, { forward: true });
    // hide document body
    // mainWindow.setFocusable(false); // Disable focusing

    // Hide window when it's not focused
    // mainWindow.on('blur', () => {
    //     mainWindow.hide();
    // });
}

let fileDragging = false;
let windowVisible = false;

const hideWindow = () => {
    windowVisible = false;
    mainWindow.setIgnoreMouseEvents(true, { forward: true });
    mainWindow.webContents.executeJavaScript('fadeOut();');
}

const showWindow = () => {
    windowVisible = true;
    mainWindow.setIgnoreMouseEvents(false);
    mainWindow.webContents.executeJavaScript('fadeIn();');
}

app.whenReady().then(() => {
    createWindow();
    
    // Listen for window control events
    ipcMain.on('show-window', () => {
        showWindow();
    });
    
    ipcMain.on('hide-window', () => {
        hideWindow();
    });

    // Listen for drag events from renderer
    ipcMain.on('dragging-file', () => {
        fileDragging = true;
        showWindow();
    });
    
    ipcMain.on('mouse-enter', () => {
        fileDragging = false;
        mainWindow.setIgnoreMouseEvents(false);
        setTimeout(() => {
            if (!fileDragging) {
                mainWindow.setIgnoreMouseEvents(true, { forward: true });
            }
        }, 50);
    });
    
    ipcMain.on('mouse-leave', () => {
        hideWindow();
    });
});

app.on('window-all-closed', () => {
    console.log('all windows closed');
    if (process.platform !== 'darwin') {
        app.quit();
    }
});
