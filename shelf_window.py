import os
from PyQt6.QtWidgets import (QMainWindow, QLabel, QVBoxLayout, QHBoxLayout,
                           QWidget, QApplication, QScrollArea, QFrame, QPushButton)
from PyQt6.QtCore import Qt, pyqtSignal, QMimeData, QUrl, QSize
from PyQt6.QtGui import (QDragEnterEvent, QDropEvent, QIcon, QPixmap,
                       QDrag, QMouseEvent, QPainter, QColor)

class FileItem(QWidget):
    """Widget representing a file/folder on the shelf with actions"""
    remove_requested = pyqtSignal(str)
    
    def __init__(self, file_path, parent=None):
        super().__init__(parent)
        self.file_path = file_path
        self.file_name = os.path.basename(file_path)
        self.is_directory = os.path.isdir(file_path)
        
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
        name_label.setStyleSheet("color: white; font-size: 9pt;")
        display_name = self.file_name if len(self.file_name) <= 12 else f"{self.file_name[:10]}.."
        name_label.setText(display_name)
        
        # Action buttons
        button_layout = QHBoxLayout()
        button_layout.setContentsMargins(0, 0, 0, 0)
        button_layout.setSpacing(2)
        
        # View button
        self.view_btn = QPushButton()
        self.view_btn.setIcon(QIcon("icons/view.png"))
        self.view_btn.setFixedSize(20, 20)
        self.view_btn.setStyleSheet("QPushButton { background: transparent; border: none; }")
        self.view_btn.clicked.connect(self.open_in_explorer)
        
        # Remove button
        self.remove_btn = QPushButton()
        self.remove_btn.setIcon(QIcon("icons/remove.png"))
        self.remove_btn.setFixedSize(20, 20)
        self.remove_btn.setStyleSheet("QPushButton { background: transparent; border: none; }")
        self.remove_btn.clicked.connect(lambda: self.remove_requested.emit(self.file_path))
        
        button_layout.addWidget(self.view_btn)
        button_layout.addWidget(self.remove_btn)
        
        # Add widgets to layout
        layout.addWidget(self.icon_label)
        layout.addWidget(name_label)
        layout.addLayout(button_layout)
        
        # Enable mouse tracking for hover effects
        self.setMouseTracking(True)
        self.setStyleSheet("""
            QLabel {
                background-color: rgba(255, 255, 255, 30);
                border-radius: 5px;
                padding: 5px;
                color: white;
            }
            QLabel:hover {
                background-color: rgba(255, 255, 255, 80);
            }
        """)
        
    def setIcon(self):
        """Set appropriate icon based on file type"""
        # Get file extension
        _, ext = os.path.splitext(self.file_path)
        ext = ext.lower()
        
        # Use Qt resource path for shelf icon
        icon_path = ":/icons/shelf_icon.png"
        
        # Check if resource exists
        if not QIcon.hasThemeIcon(icon_path):
            print(f"Warning: Shelf icon resource not found at {icon_path}")
            # Use a generic document icon or create a simple one
            icon = QIcon.fromTheme("document")
            if icon.isNull():
                # Create a simple document icon
                pixmap = QPixmap(48, 48)
                pixmap.fill(Qt.GlobalColor.white)
                icon = QIcon(pixmap)
        else:
            print(f"Loading shelf icon from: {icon_path}")
            icon = QIcon(icon_path)
        
        # Try to use system icon if available
        if os.path.exists(self.file_path):
            system_icon = QIcon.fromTheme(self.file_path)
            if not system_icon.isNull():
                icon = system_icon
        
        # Create pixmap from icon
        pixmap = icon.pixmap(QSize(48, 48))
        self.icon_label.setPixmap(pixmap)
        
    def mousePressEvent(self, event: QMouseEvent):
        """Handle mouse press to start drag operation"""
        if event.button() == Qt.MouseButton.LeftButton:
            self.drag_start_position = event.pos()
    
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
        
        # Execute drag
        drag.exec(Qt.DropAction.CopyAction | Qt.DropAction.MoveAction)

class ShelfWindow(QMainWindow):
    file_taken = pyqtSignal(str)
    
    def __init__(self):
        super().__init__()
        self.stored_files = []  # List to store file paths
        self.init_ui()
        self.setAcceptDrops(True)
        self.show()  # Start visible
    
    def init_ui(self):
        self.setWindowTitle("Dropp - File Shelf")
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint |
                          Qt.WindowType.WindowStaysOnTopHint |
                          Qt.WindowType.Tool)
        
        # Set background to semi-transparent dark color
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedHeight(120)  # Fixed height, width will adjust to content
        self.setMinimumWidth(300)
        self.setWindowOpacity(0.8)  # More visible than before
        
        # Position at top-right near menu bar
        screen = QApplication.primaryScreen().availableGeometry()
        self.move(screen.right() - self.width() - 20, screen.top() + 40)
        
        # Setup central widget with background
        central_widget = QWidget()
        central_widget.setObjectName("centralWidget")
        central_widget.setStyleSheet("""
            #centralWidget {
                background-color: rgba(40, 40, 40, 180);
                border-radius: 10px;
                border: 1px solid rgba(255, 255, 255, 50);
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
        self.files_layout.setSpacing(10)
        self.files_layout.setAlignment(Qt.AlignmentFlag.AlignLeft)
        
        # Add placeholder text when empty
        self.placeholder_label = QLabel("Drop files here")
        self.placeholder_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.placeholder_label.setStyleSheet("color: rgba(255, 255, 255, 150); font-size: 14px;")
        self.files_layout.addWidget(self.placeholder_label)
        
        scroll_area.setWidget(self.files_container)
        main_layout.addWidget(scroll_area)
        
        self.setCentralWidget(central_widget)
    
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            self.setWindowOpacity(1.0)  # Fully visible on drag
            self.raise_()
            event.acceptProposedAction()
    
    def dragLeaveEvent(self, event):
        self.setWindowOpacity(0.8)  # Return to semi-transparent
    
    def dropEvent(self, event: QDropEvent):
        urls = event.mimeData().urls()
        for url in urls:
            file_path = url.toLocalFile()
            if file_path and os.path.exists(file_path):
                self.add_file_to_shelf(file_path)
        
        self.setWindowOpacity(0.8)  # Return to semi-transparent after drop
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
        self.files_layout.addWidget(file_item)
        
        # Adjust window width if needed
        self.adjustSize()
        
        # Emit signal
        self.file_taken.emit(file_path)
    
    def paintEvent(self, event):
        """Custom paint event to create rounded corners"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(0, 0, 0, 0))  # Transparent
        painter.drawRect(self.rect())
