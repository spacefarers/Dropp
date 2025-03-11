import sys
import platform
import os
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QMessageBox
from PyQt6.QtGui import QIcon, QAction, QShortcut, QPixmap
from shelf_window import ShelfWindow

if platform.system() == 'Darwin':
    from AppKit import NSApp, NSApplicationActivationPolicyAccessory

class TrayApp:
    def __init__(self):
        # Force xcb platform plugin for Linux compatibility
        self.app = QApplication(['--platform', 'xcb'] + sys.argv)
        
        # Hide dock icon on macOS
        if platform.system() == 'Darwin':
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
            
        self.app.setQuitOnLastWindowClosed(False)  # Keep app running
        
        # Create tray icon with proper path
        icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons", "tray_icon.png")
        
        # Check if icon file exists
        if not os.path.exists(icon_path):
            print(f"Warning: Tray icon not found at {icon_path}")
            # Create a fallback icon
            pixmap = QPixmap(16, 16)
            pixmap.fill(self.app.palette().color(self.app.palette().ColorRole.Window))
            self.tray_icon = QSystemTrayIcon(QIcon(pixmap))
        else:
            print(f"Loading tray icon from: {icon_path}")
            self.tray_icon = QSystemTrayIcon(QIcon(icon_path))
        self.shelf_window = ShelfWindow()
        
        # Setup system tray
        menu = QMenu()
        show_action = QAction("Show Shelf", self.app)
        show_action.triggered.connect(self.toggle_shelf)
        menu.addAction(show_action)
        
        # Add about action
        about_action = QAction("About", self.app)
        about_action.triggered.connect(self.show_about)
        menu.addAction(about_action)
        
        # Add separator
        menu.addSeparator()
        
        quit_action = QAction("Quit", self.app)
        quit_action.triggered.connect(self.app.quit)
        menu.addAction(quit_action)
        
        self.tray_icon.setContextMenu(menu)
        
        # Make tray icon clickable to show/hide shelf
        self.tray_icon.activated.connect(self.tray_activated)
        
        # Add Ctrl+Q shortcut to quit
        quit_shortcut = QShortcut("Ctrl+Q", self.app)
        quit_shortcut.activated.connect(self.app.quit)
        self.tray_icon.show()
        
        # Connect shelf window signals
        self.shelf_window.file_taken.connect(self.on_file_taken)
    
    def toggle_shelf(self):
        """Toggle shelf visibility"""
        if self.shelf_window.isVisible():
            self.shelf_window.hide()
        else:
            self.shelf_window.show()
            self.shelf_window.raise_()
    
    def tray_activated(self, reason):
        """Handle tray icon activation"""
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.toggle_shelf()
    
    def on_file_taken(self, file_path):
        """Handle file being added to shelf"""
        # Show notification
        self.tray_icon.showMessage(
            "File Added",
            f"Added to shelf: {os.path.basename(file_path)}",
            QSystemTrayIcon.MessageIcon.Information,
            2000  # 2 seconds
        )
    
    def show_about(self):
        """Show about dialog"""
        QMessageBox.about(
            None,
            "About Dropp",
            "Dropp - Persistent File Shelf\n\n"
            "A utility for temporarily storing files that can be "
            "dragged between applications.\n\n"
            "© 2025"
        )

    def run(self):
        self.app.exec()

if __name__ == "__main__":
    tray_app = TrayApp()
    tray_app.run()
