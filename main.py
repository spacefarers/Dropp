import sys
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QAction
from shelf_window import ShelfWindow

class TrayApp:
    def __init__(self):
        self.app = QApplication(sys.argv)
        self.tray_icon = QSystemTrayIcon(QIcon(":/icons/tray_icon.png"))
        self.shelf_window = ShelfWindow()
        
        # Setup system tray
        menu = QMenu()
        quit_action = QAction("Quit", self.app)
        quit_action.triggered.connect(self.app.quit)
        menu.addAction(quit_action)
        
        self.tray_icon.setContextMenu(menu)
        self.tray_icon.show()
        
        # Connect shelf window signals
        self.shelf_window.file_taken.connect(self.hide_shelf)

    def hide_shelf(self, file_path):
        self.shelf_window.hide()

    def run(self):
        self.app.exec()

if __name__ == "__main__":
    tray_app = TrayApp()
    tray_app.run()
