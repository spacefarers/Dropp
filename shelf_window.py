import os
import sys
import subprocess
from PyQt6.QtWidgets import (QMainWindow, QLabel, QVBoxLayout, QHBoxLayout,
                           QWidget, QApplication, QScrollArea, QFrame, QPushButton,
                           QSizePolicy, QGraphicsOpacityEffect)
from PyQt6.QtCore import Qt, pyqtSignal, QMimeData, QUrl, QSize, QPropertyAnimation, QEasingCurve
from PyQt6.QtGui import (QDragEnterEvent, QDropEvent, QIcon, QPixmap,
                       QDrag, QMouseEvent, QPainter, QColor)

class FileItem(QWidget):
    """Widget representing a file/folder on the shelf with actions"""
    remove_requested = pyqtSignal(str)
    
    def __init__(self, file_path, parent=None):
        super().__init__(parent)
        self.file_path = file_path
        print(f"Creating FileItem for: {file_path}")
        print(f"File path in FileItem: {self.file_path}")
        normalized_file_path = os.path.normpath(self.file_path)
        self.file_name = os.path.basename(normalized_file_path)
        self.is_directory = os.path.isdir(self.file_path)
        
        # Main widget setup
        self.setFixedSize(80, 110)
        self.setToolTip(self.file_name)
        self.setAcceptDrops(True)
        
        # Create layouts
        layout = QVBoxLayout(self)
        layout.setContentsMargins(2, 2, 2, 2)
        layout.setSpacing(4)
        
        # Icon display
        self.icon_label = QLabel()
        self.icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setIcon()
        
        # File name label
        name_label = QLabel()
        name_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        name_label.setStyleSheet("""
            color: black;
            font-size: 9pt;
            font-weight: 500;
            padding: 2px;
        """)
        # Always show extension
        name, ext = os.path.splitext(self.file_name)
        display_name = f"{name[:7]}..{ext}" if len(name) > 7 else self.file_name
        name_label.setText(display_name)
        print(f"File name: {self.file_name}, Display name: {display_name}, is_directory: {self.is_directory}")
        name_label.setToolTip(self.file_name)  # Show full name in tooltip
        
        # Top buttons layout
        top_button_layout = QHBoxLayout()
        top_button_layout.setContentsMargins(2, 0, 2, 0)
        top_button_layout.setSpacing(2)
        
        # Reveal in Finder/Explorer button
        self.reveal_btn = QPushButton()
        self.reveal_btn.setIcon(QIcon("icons/magnify.png"))
        self.reveal_btn.setIconSize(QSize(12, 12))
        self.reveal_btn.setFixedSize(16, 16)
        self.reveal_btn.setStyleSheet("""
            QPushButton {
                background: rgba(255, 255, 255, 0.9);
                border: none;
                border-radius: 8px;
                padding: 2px;
            }
            QPushButton:hover {
                background: rgba(255, 255, 255, 1);
            }
        """)
        self.reveal_btn.clicked.connect(self.open_in_explorer)
        
        # Remove button
        self.remove_btn = QPushButton()
        self.remove_btn.setIcon(QIcon("icons/remove.png"))
        self.remove_btn.setIconSize(QSize(12, 12))
        self.remove_btn.setFixedSize(16, 16)
        self.remove_btn.setStyleSheet("""
            QPushButton {
                background: rgba(255, 255, 255, 0.9);
                border: none;
                border-radius: 8px;
                padding: 2px;
            }
            QPushButton:hover {
                background: rgba(255, 255, 255, 1);
            }
        """)
        self.remove_btn.clicked.connect(lambda: self.remove_requested.emit(self.file_path))
        
        # Add buttons to top layout
        top_button_layout.addWidget(self.reveal_btn)
        top_button_layout.addWidget(self.remove_btn)
        top_button_layout.addStretch()
        
        # Add widgets to layout with proper spacing
        layout.addLayout(top_button_layout)
        layout.addWidget(self.icon_label)
        layout.addWidget(name_label)
        layout.setSpacing(4)
        layout.setContentsMargins(2, 2, 2, 2)
        
        # Enable mouse tracking for hover effects
        self.setMouseTracking(True)
        self.setStyleSheet("""
            QLabel {
                background-color: rgba(255, 255, 255, 200);
                border-radius: 5px;
                padding: 5px;
                color: black;
                border: 1px solid rgba(0, 0, 0, 0.1);
            }
            QLabel:hover {
                background-color: rgba(255, 255, 255, 230);
                border-color: rgba(0, 0, 0, 0.2);
            }
        """)
        
    def open_in_explorer(self):
        """Open file in system file explorer"""
        if os.path.exists(self.file_path):
            if os.name == 'nt':  # Windows
                os.startfile(os.path.dirname(self.file_path))
            elif os.name == 'posix':  # macOS/Linux
                if sys.platform == 'darwin':
                    subprocess.run(['open', '-R', self.file_path])
                else:
                    subprocess.run(['xdg-open', os.path.dirname(self.file_path)])
        
    def setIcon(self):
        """Set appropriate icon based on file type"""
        # Use local icon path
        if self.is_directory:
            icon = QIcon.fromTheme("folder")
        else:
            icon = QIcon.fromTheme("document")
        
        # No system icon logic for now, directly use the determined icon
        
        # Create pixmap from icon
        pixmap = icon.pixmap(QSize(48, 48))
        self.icon_label.setPixmap(pixmap)
        

    def mousePressEvent(self, event: QMouseEvent):
        """Handle mouse press to start drag operation"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start_position = event.pos()
    
    # New signal for drag completion
    file_dragged_out = pyqtSignal(str)
    
    def mousePressEvent(self, event: QMouseEvent):
        """Handle mouse press to start drag operation"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start_position = event.pos()
    
    # New signal for drag completion
    file_dragged_out = pyqtSignal(str)
    
    def mouseMoveEvent(self, event: QMouseEvent):
        """Handle mouse move to perform drag operation"""
        if not (event.buttons() & Qt.MouseButton.LeftButton):
            return
            
        # Check if drag threshold is met
        if (event.pos() - self.drag_start_position).manhattanLength() < QApplication.startDragDistance():
            return
            
        # Start drag operation
        drag = QDrag(self)
        mime_data = QMimeData()
        
        # Add URL to mime data
        url = QUrl.fromLocalFile(self.file_path)
        mime_data.setUrls([url])
        
        # Set drag pixmap
        pixmap = self.grab()
        drag.setPixmap(pixmap)
        drag.setHotSpot(event.pos())
        drag.setMimeData(mime_data)
        
        # Execute drag operation
        print(f"Starting drag operation for {self.file_path}")
        result = drag.exec(Qt.DropAction.MoveAction | Qt.DropAction.CopyAction)
        print(f"Drag completed with result: {result}")
        
        # Always emit the signal when drag is completed
        # This ensures the file is always removed from shelf when dragged out
        self.file_dragged_out.emit(self.file_path)
        print(f"Emitted file_dragged_out signal for {self.file_path}")

class ShelfWindow(QMainWindow):
    file_taken = pyqtSignal(str)

    def showOverlay(self):
        self.overlay.resize(self.width(), self.height())
        self.overlay.move(0, 0)
        self.overlay.show()
    
    def __init__(self):
        super().__init__()
        self.stored_files = []  # List to store file paths
        self.num_items = 0  # Centralized item count
        self.init_ui()
        self.setAcceptDrops(True)
        self.show()  # Start visible
        self.raise_()  # Bring to front
        
        # Create overlay label
        self.overlay = QLabel("", self.centralWidget())
        self.overlay.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.overlay.hide()
        self.overlay.setStyleSheet("""
            background-color: rgba(50, 50, 50, 200);
            color: white;
            font-size: 24px;
            border-radius: 10px;
            padding: 20px;
        """)
        opacity = QGraphicsOpacityEffect()
        opacity.setOpacity(0.7)
        self.overlay.setGraphicsEffect(opacity)
        self.overlay.raise_()
    
    def init_ui(self):
        self.setWindowTitle("Dropp - File Shelf")
        self.set_window_flags(always_on_top=True)
        
        # Set background to semi-transparent dark color
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        # Set initial size for 1 file (80px item + 10px spacing + 20px margins = 110px)
        self.item_width = 80
        self.item_spacing = 10
        self.window_margin = 0
        initial_width = self.window_margin
        self.num_items = 0  # Initialize item count
        
        self.setFixedHeight(160)
        self.setMinimumWidth(initial_width)
        self.setWindowOpacity(0.95)
        
        # Animation properties
        self.animation = QPropertyAnimation(self, b"geometry")
        self.animation.setDuration(200)  # 200ms animation
        self.animation.setEasingCurve(QEasingCurve.Type.OutQuad)
        
        # Position at top-right near menu bar
        screen = QApplication.primaryScreen().availableGeometry()
        self.initial_x = screen.right() - initial_width - 40
        self.move(self.initial_x, screen.top() + 40)
        
        # Setup central widget with background
        central_widget = QWidget()
        central_widget.setObjectName("centralWidget")
        central_widget.setStyleSheet("""
            #centralWidget {
                background-color: rgba(50, 50, 50, 230);
                border-radius: 10px;
                border: 1px solid rgba(255, 255, 255, 50);
                box-shadow: 0px 1px 4px rgba(0, 0, 0, 0.1);
                padding: 5px;
            }
        """)
        
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(10, 10, 10, 10)
        
        # Create scroll area for files
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setFrameShape(QFrame.Shape.NoFrame)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        
        # Container for file items
        self.files_container = QWidget()
        self.files_layout = QHBoxLayout(self.files_container)
        self.files_layout.setSpacing(5)
        self.files_layout.setAlignment(Qt.AlignmentFlag.AlignLeft)
        
        # Add placeholder text when empty
        self.placeholder_label = QLabel("Drop files here")
        self.placeholder_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.placeholder_label.setStyleSheet("""
            color: rgba(0, 0, 0, 0.6);
            font-size: 14px;
            font-weight: 500;
            padding: 8px;
            background-color: rgba(255, 255, 255, 0.9);
            border-radius: 5px;
            border: 1px solid rgba(0, 0, 0, 0.1);
            margin: 0;
        """)
        self.placeholder_label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.files_layout.addWidget(self.placeholder_label)
        
        scroll_area.setWidget(self.files_container)
        main_layout.addWidget(scroll_area)
        
        self.setCentralWidget(central_widget)
    
    def update_window_width(self):
        """
        Central method to update window width based on absolute metrics.
        Uses the number of items to calculate the appropriate width.
        """
        # Calculate exact width needed based on the absolute number of items
        new_width = self.num_items * (self.item_width + self.item_spacing) + self.window_margin
        
        # Calculate position to maintain right edge alignment
        screen = QApplication.primaryScreen().availableGeometry()
        new_x = screen.right() - new_width - 40
        
        # Animate both size and position
        self.animation.stop()
        new_geometry = self.geometry()
        # new_geometry.setWidth(new_width)
        new_geometry.setX(new_x)
        self.animation.setStartValue(self.geometry())
        self.animation.setEndValue(new_geometry)
        self.animation.start()
        
        return new_width
    
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            self.showOverlay()
            self.overlay.raise_()
            event.acceptProposedAction()
    
    def dragLeaveEvent(self, event):
        self.overlay.hide()
    
    def dropEvent(self, event: QDropEvent):
        urls = event.mimeData().urls()
        for url in urls:
            file_path = url.toLocalFile()
            if file_path and os.path.exists(file_path):
                self.add_file_to_shelf(file_path)
        
        self.overlay.hide()
        event.acceptProposedAction()
    
    def add_file_to_shelf(self, file_path):
        """Add a file to the shelf"""
        # Remove placeholder if it exists
        if self.placeholder_label.isVisible():
            self.placeholder_label.setVisible(False)
            self.files_layout.removeWidget(self.placeholder_label)
        
        # Check if file already exists on shelf
        if file_path in self.stored_files:
            return
        
        # Add file to storage
        self.stored_files.append(file_path)
        
        # Create file item widget
        file_item = FileItem(file_path)
        file_item.remove_requested.connect(self.remove_file_from_shelf)
        file_item.file_dragged_out.connect(self.remove_file_from_shelf)
        self.files_layout.addWidget(file_item)
        
        # Update item count and window width
        self.num_items += 1
        self.update_window_width()
    
    def remove_file_from_shelf(self, file_path):
        """Remove a file from the shelf"""
        if file_path in self.stored_files:
            self.stored_files.remove(file_path)
            
            # Find and remove the corresponding widget
            for i in range(self.files_layout.count()):
                widget = self.files_layout.itemAt(i).widget()
                if isinstance(widget, FileItem) and widget.file_path == file_path:
                    widget.deleteLater()
                    self.files_layout.removeWidget(widget)
                    break
            
            # Show placeholder if shelf is empty
            if not self.stored_files:
                self.placeholder_label.setVisible(True)
                self.files_layout.addWidget(self.placeholder_label)
            
            # Update item count and window width
            self.num_items -= 1
            self.update_window_width()

    def paintEvent(self, event):
        """Custom paint event to create rounded corners"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(0, 0, 0, 0))  # Transparent
        painter.drawRect(self.rect())

    def set_window_flags(self, always_on_top=True):
        """Set window flags with optional always-on-top behavior"""
        flags = Qt.WindowType.FramelessWindowHint
        if always_on_top:
            flags |= Qt.WindowType.WindowStaysOnTopHint
        self.setWindowFlags(flags)
        self.show()  # Required to apply new flags

    def toggle_always_on_top(self):
        """Toggle always-on-top behavior"""
        current_flags = self.windowFlags()
        if current_flags & Qt.WindowType.WindowStaysOnTopHint:
            self.set_window_flags(always_on_top=False)
        else:
            self.set_window_flags(always_on_top=True)
