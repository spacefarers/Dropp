const { app, BrowserWindow, ipcMain, screen } = require('electron');
const {join} = require("path");
let mainWindow;

function createWindow() {
    console.log('Creating main window...');
    mainWindow = new BrowserWindow({
        width: 200,
        height: 400,
        webPreferences: {
            preload: join(__dirname, 'preload.js'),
        },
        transparent: true,
        frame: false,
        alwaysOnTop: true,
        hasShadow: false,
        resizable: false,
        skipTaskbar: true,
        focusable: false,
        show: false // Start hidden
    });

    const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;
    const x = screenWidth - mainWindow.getBounds().width;
    const y = (screenHeight / 2) - (mainWindow.getBounds().height / 2);
    mainWindow.setPosition(x, y);
    
    console.log('Loading index.html...');
    mainWindow.loadFile('index.html')
        .then(() => {
            console.log('Window loaded, setting initial state...');
            mainWindow.setIgnoreMouseEvents(true, { forward: true });
            mainWindow.webContents.executeJavaScript('document.body.style.opacity = 0;');
            mainWindow.show(); // Show after initial setup
            console.log('Window should now be visible');
        })
        .catch(err => {
            console.error('Failed to load window:', err);
        });
}

let fileDragging = false;
let windowVisible = false;

const hideWindow = () => {
    console.log('Hiding window...');
    windowVisible = false;
    mainWindow.setIgnoreMouseEvents(true, { forward: true });
    mainWindow.webContents.executeJavaScript('fadeOut();')
        .then(() => console.log('Fade out complete'))
        .catch(err => console.error('Fade out failed:', err));
}

const showWindow = () => {
    console.log('Showing window...');
    if (!windowVisible) {
        windowVisible = true;
        mainWindow.setIgnoreMouseEvents(false);
        mainWindow.webContents.executeJavaScript('fadeIn();')
            .then(() => console.log('Fade in complete'))
            .catch(err => console.error('Fade in failed:', err));
    }
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
