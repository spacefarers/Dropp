const {app, BrowserWindow, nativeImage, screen} = require("electron");
const {autoUpdater} = require("electron-updater");
const Store = require("electron-store");
const configOptions = require("./configOptions");

const {Instance} = require("./Window");
const {setShortcut} = require("./Shortcut");
const {droppointDefaultIcon} = require("./Icons");
const {setTray} = require("./Tray");

const config = new Store(configOptions);
let splashScreen;

app
    .on("ready", () => {
        // Splash screen which also helps to run in background and keep app alive
        const {width,height} = screen.getPrimaryDisplay().workAreaSize;
        splashScreen = new BrowserWindow({
            width: 1000,
            height: 200,
            frame: false,
            titleBarStyle: "hidden",
            fullscreenable: false,
            transparent: true,
            movable: false,
            icon: nativeImage.createFromPath(droppointDefaultIcon),
            show: false,
        });
        // splashScreen.loadFile(path.join(__dirname, "../static/media/splash.jpeg"));
        // splashScreen.removeMenu();
        // setTimeout(() => {
        //   splashScreen.hide();
        // }, 3000);

        // screen.on('display-metrics-changed', (event, display, changedMetrics) =>
        // {
        //     console.log(display, changedMetrics);
        //     const {x, y, width, height} = display.workArea;
        //     console.log(x, y, width, height);
        //     splashScreen.setBounds({x: width - 500, y: height - 450, width: 500, height: 500})
        // });

        setTray();
        setShortcut();

        if (BrowserWindow.getAllWindows.length === 0 && config.get("spawnOnLaunch")) {
            const instance = new Instance();
            const instanceID = instance.createNewWindow();
            if (instanceID !== null) {
            }
        }
    })
    // .on("activate", () => {
    //   autoUpdater.checkForUpdatesAndNotify();
    //   if (BrowserWindow.getAllWindows.length === 0) {
    //     createMainWindow();
    //   }
    // })
    .on("before-quit", () => {
        splashScreen.close();
    })
    .on("will-quit", () => {
        globalShortcut.unregisterAll();
    });
module.exports = {
    whenReady: app.whenReady,
};

// const { ipcMain } = require('electron');

// ipcMain.on('file-drag-started', () => {
//     console.log('File drag started')
//     const instance = new Instance();
//     instance.createNewWindow();
// });
