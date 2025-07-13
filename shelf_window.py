import os
import sys
import subprocess
import boto3
import json
import hashlib
from settings_dialog import SettingsDialog
from PyQt6.QtCore import QFileInfo
from PyQt6.QtWidgets import (QMainWindow, QLabel, QVBoxLayout, QHBoxLayout,
                           QWidget, QApplication, QScrollArea, QFrame, QPushButton, QMenu,
                           QSizePolicy, QGraphicsOpacityEffect, QFileIconProvider, QStyle)
from PyQt6.QtCore import Qt, pyqtSignal, QMimeData, QUrl, QSize, QPropertyAnimation, QEasingCurve
from PyQt6.QtGui import (QDragEnterEvent, QDropEvent, QIcon, QPixmap,
                       QDrag, QMouseEvent, QPainter, QColor, QPainterPath)
from settings_dialog import APP_SUPPORT_DIR, SETTINGS_FILE
        
def calculate_size(file_path):
    """Calculate file size of local file"""
    try:
        return os.path.getsize(file_path)
    except Exception as e:
        print(f"Error calculating size for {file_path}: {e}")
        return -1

class ToggleButton(QWidget):
    """Custom button widget for hiding/showing the shelf window"""
    clicked = pyqtSignal()
    
    def __init__(self, parent=None, expanded=True):
        super().__init__(parent)
        self.setFixedWidth(12)
        self.expanded = expanded
        self.setToolTip("Click to hide shelf" if expanded else "Click to show shelf")
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        # Set background color
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(40, 40, 40, 200))
        painter.drawRect(0, 0, self.width(), self.height())
        
        # Draw arrow icon in the middle of the button
        painter.setPen(QColor(200, 200, 200))
        painter.setBrush(QColor(200, 200, 200))
        
        # Draw left or right-facing arrow based on expanded state
        arrow_width = 6
        arrow_height = 10
        x = (self.width() - arrow_width) // 2
        y = (self.height() - arrow_height) // 2
        
        path = QPainterPath()
        if self.expanded:
            # Right-facing arrow (hide)
            path.moveTo(x, y)
            path.lineTo(x + arrow_width, y + arrow_height // 2)
            path.lineTo(x, y + arrow_height)
        else:
            # Left-facing arrow (show)
            path.moveTo(x + arrow_width, y)
            path.lineTo(x, y + arrow_height // 2)
            path.lineTo(x + arrow_width, y + arrow_height)
        
        path.closeSubpath()
        painter.drawPath(path)
    
    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
            self.expanded = not self.expanded
            self.setToolTip("Click to hide shelf" if self.expanded else "Click to show shelf")
            self.update()

class FileItem(QWidget):
    """Widget representing a file/folder on the shelf with actions"""
    remove_requested = pyqtSignal(str)
    cloud_upload_requested = pyqtSignal(str)
    
    def __init__(self, file_path, parent=None):
        super().__init__(parent)
        self.parent = parent
        self.file_path = file_path
        self.status = "local"  # local/cloud/both/mismatch
        self.local_size = calculate_size(file_path)
        self.cloud_size = None
        print(f"Creating FileItem for: {file_path}")
        print(f"File path in FileItem: {self.file_path}")
        normalized_file_path = os.path.normpath(self.file_path)
        self.file_name = os.path.basename(normalized_file_path)
        self.is_directory = os.path.exists(self.file_path) and os.path.isdir(self.file_path)
        
        # Main widget setup
        self.setFixedSize(85, 130)
        self.setToolTip(self.file_name)
        self.setAcceptDrops(True)
        
        # Create layouts
        layout = QVBoxLayout(self)
        
        # Set consistent width for all elements
        self.element_width = 80
        
        # Preview display
        self.preview_container = QWidget()
        self.preview_container.setFixedSize(self.element_width, 64)
        preview_layout = QHBoxLayout(self.preview_container)
        preview_layout.setContentsMargins(0, 0, 0, 0)
        preview_layout.setSpacing(0)
        
        # Create a label to display the preview
        self.preview_label = QLabel()
        self.preview_label.setFixedSize(self.element_width, 64)
        self.preview_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.preview_label.setScaledContents(True)
        
        # Set the preview based on file status
        self.update_preview()
        
        preview_layout.addWidget(self.preview_label)
        
        # File name label
        name_label = QLabel()
        name_label.setFixedWidth(self.element_width)
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
        
        # Top buttons layout with fixed width container
        button_container = QWidget()
        button_container.setFixedWidth(self.element_width)
        top_button_layout = QHBoxLayout(button_container)
        top_button_layout.setContentsMargins(0, 0, 0, 0)
        top_button_layout.setSpacing(2)
        
        style = QApplication.instance().style()
        # Reveal in Finder/Explorer button
        self.reveal_btn = QPushButton()
        reveal_icon = QStyle.StandardPixmap.SP_FileDialogContentsView
        self.reveal_btn.setIcon(style.standardIcon(reveal_icon))
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
        trash_icon = QStyle.StandardPixmap.SP_DockWidgetCloseButton  # Use the StandardPixmap enumeration
        self.remove_btn.setIcon(style.standardIcon(trash_icon))
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
        
        # cloud upload button
        self.cloud_upload_button = QPushButton()
        upload_icon = QStyle.StandardPixmap.SP_ArrowUp  # Use the StandardPixmap enumeration
        self.cloud_upload_button.setIcon(style.standardIcon(upload_icon))
        self.cloud_upload_button.setIconSize(QSize(12, 12))
        self.cloud_upload_button.setFixedSize(16, 16)
        self.cloud_upload_button.setStyleSheet("""        
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
        self.cloud_upload_button.clicked.connect(lambda: self.cloud_upload_requested.emit(self.file_path))

        self.cloud_download_button = QPushButton()
        download_icon = QStyle.StandardPixmap.SP_ArrowDown
        self.cloud_download_button.setIcon(style.standardIcon(download_icon))
        self.cloud_download_button.setIconSize(QSize(12, 12))
        self.cloud_download_button.setFixedSize(16, 16)
        self.cloud_download_button.setStyleSheet("""        
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
        self.cloud_download_button.clicked.connect(lambda: self.download_file_from_s3(self.file_path))



        # Add buttons to top layout with equal spacing
        top_button_layout.addWidget(self.reveal_btn)
        top_button_layout.addWidget(self.remove_btn)
        top_button_layout.addWidget(self.cloud_upload_button)
        top_button_layout.addWidget(self.cloud_download_button)
        # Add stretch to ensure buttons are aligned left
        top_button_layout.addStretch()
        
        # Add widgets to layout with proper spacing and alignment
        layout.addWidget(button_container, 0, Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.preview_container, 0, Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(name_label, 0, Qt.AlignmentFlag.AlignCenter)
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
        
        # Initialize the preview
        self.update_preview()
        self.update_status()
        
        # Cloud download function (placeholder - implementation needed)
    def download_file_from_s3(self, file_path):
        """Download a file from S3 bucket to local downloads folder"""
        print(f"Download file from S3: {file_path}")
        s3_settings = self.parent.load_settings()
        if not s3_settings.get("s3_enabled"):
            print("S3 download is not enabled in settings.")
            return

        bucket_name = s3_settings.get("s3_bucket_name")
        access_key = s3_settings.get("aws_access_key")
        secret_key = s3_settings.get("aws_secret_key")
        region = s3_settings.get("aws_region")

        if not all([bucket_name, access_key, secret_key, region]):
            print("Missing S3 settings. Please check settings dialog.")
            return

        try:
            s3 = boto3.client(
                's3',
                aws_access_key_id=access_key,
                aws_secret_access_key=secret_key,
                region_name=region,
                endpoint_url=s3_settings.get("s3_gateway_url") or None
            )

            # Get the file name (key) for S3
            file_name = os.path.basename(file_path)

            # Determine download directory
            downloads_dir = os.path.join(os.path.expanduser("~"), "Downloads")
            local_file_path = os.path.join(downloads_dir, file_name)

            # Download the file from S3
            print(f"Downloading from S3 bucket: {bucket_name}, key: {file_name} to local path: {local_file_path}")
            s3.download_file(bucket_name, file_name, local_file_path)
            print(f"Successfully downloaded {file_name} from S3 to {local_file_path}")

            # Calculate the size of the downloaded file
            downloaded_size = calculate_size(local_file_path)

            # Update parent.parent.server_files with local path
            s3_file_key = file_name # Use file_name as key
            if s3_file_key in self.parent.parent.server_files:
                self.parent.parent.server_files[s3_file_key]['local_path'] = local_file_path
            else:
                # This case should ideally not happen, but handle it just in case.
                self.parent.parent.server_files[s3_file_key] = {'local_path': local_file_path, 'size': None}
            self.parent.parent.flush_server_files()
            self.parent.render_server_files()
            self.file_path = local_file_path
            self.update_preview()

        except Exception as e:
            print(f"Error downloading from S3: {e}")

        # No need to call update_server_files_local_path here, already handled in download function
        # self.update_server_files_local_path(file_name, local_file_path) # Removed this line
        pass # replaced with pass since the update is already handled in download_file_from_s3

    def update_server_files_local_path(self, s3_file_key, local_file_path):
        """Update server_files with local path and size, and re-render"""
        print(f"Update server_files for {s3_file_key} with local path {local_file_path}")
        if not hasattr(self.parent, 'server_files'):
            print("Parent does not have server_files attribute.")
            return

        if s3_file_key in self.parent.server_files:
            self.parent.server_files[s3_file_key]['local_path'] = local_file_path
            local_size = calculate_size(local_file_path)
            self.parent.server_files[s3_file_key]['size'] = local_size
            print(f"Updated server_files for {s3_file_key} with local path and checksum.")
            self.parent.flush_server_files()
            self.render_server_files()
        else:
            print(f"S3 file key {s3_file_key} not found in server_files.")
        
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
    
    
    def update_status(self):
        # updates top row of buttons based on status
        print(f"Updating status for {self.file_path}: {self.status}")
        if self.status == "local":
            self.reveal_btn.show()
            self.remove_btn.show()
            self.cloud_upload_button.show()
            self.cloud_download_button.hide()
        elif self.status == "cloud":
            self.reveal_btn.hide()
            self.remove_btn.show()
            self.cloud_upload_button.hide()
            self.cloud_download_button.show()
        elif self.status == "both":
            self.reveal_btn.show()
            self.remove_btn.show()
            self.cloud_upload_button.hide()
            self.cloud_download_button.hide()
        elif self.status == "mismatch":
            self.reveal_btn.show()
            self.remove_btn.show()
            self.cloud_upload_button.show()
            self.cloud_download_button.show()
        
        # Update the preview based on the status
        self.update_preview()
        
    def update_file_status(self, status, cloud_size=None):
        """Update file status and cloud size"""
        self.status = status
        
        self.update_status()
        self.update_preview()
        

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
    
    def update_preview(self):
        """Update the preview based on file status"""
        pixmap = self.get_system_preview()
        self.preview_label.setPixmap(pixmap)
        self.preview_label.setStyleSheet("""        
            background-color: rgba(255, 255, 255, 100);
            border: 1px solid rgba(0, 0, 0, 0.2);
            border-radius: 5px;
        """)
    
    def get_system_preview(self):
        """Get system preview for the file"""
        try:
            if not os.path.exists(self.file_path):
                # Fallback for non-existent files
                ext = os.path.splitext(self.file_path)[1].lower()
                if ext:
                    # Try to get icon by file extension
                    temp_file_path = f"temp{ext}"
                    temp_file_info = QFileInfo(temp_file_path)
                    icon_provider = QFileIconProvider()
                    icon = icon_provider.icon(temp_file_info)
                    pixmap = icon.pixmap(64, 64)
                    if not pixmap.isNull():
                        return pixmap
                
                # If extension doesn't work or no extension, use generic file icon
                style = QApplication.instance().style()
                generic_icon = style.standardIcon(QStyle.SP_FileIcon)
                return generic_icon.pixmap(64, 64)
            
            # Get system preview using QFileIconProvider
            icon_provider = QFileIconProvider()
            file_info = QFileInfo(self.file_path)
            icon = icon_provider.icon(file_info)
            
            # Convert QIcon to QPixmap
            pixmap = icon.pixmap(64, 64)
            if pixmap.isNull():
                # If system provided a null pixmap, use generic folder or file icon
                style = QApplication.instance().style()
                fallback_icon = style.standardIcon(QStyle.SP_DirIcon if self.is_directory else QStyle.SP_FileIcon)
                return fallback_icon.pixmap(64, 64)
            return pixmap

        except Exception as e:
            print(f"Error getting system preview: {e}")
            # Fallback to a generic file icon in case of an error
            style = QApplication.instance().style()
            fallback_icon = style.standardIcon(QStyle.SP_FileIcon)
            return fallback_icon.pixmap(64, 64)

class ShelfWindow(QMainWindow):
    file_taken = pyqtSignal(str)

    def showOverlay(self):
        self.overlay.resize(self.width(), self.height())
        self.overlay.move(0, 0)
        self.overlay.show()
    
    def __init__(self, parent=None):
        super().__init__()
        self.parent = parent
        self.stored_files = []  # List to store file paths
        # We'll use parent.server_files instead of storing our own copy
        self.num_items = 0  # Centralized item count
        self.settings = self.load_settings() # Load settings here
        
        # Shelf state (expanded or collapsed)
        self.is_expanded = True
        self.collapsed_width = 12  # Width when collapsed
        
        # Edge button for show/hide (create this before init_ui)
        self.toggle_button = ToggleButton(self, self.is_expanded)
        self.toggle_button.clicked.connect(self.toggle_expansion)
        
        # Set animation for show/hide
        self.expansion_animation = QPropertyAnimation(self, b"geometry")
        self.expansion_animation.setDuration(250)  # 250ms animation
        self.expansion_animation.setEasingCurve(QEasingCurve.Type.OutCubic)
        
        # Initialize UI components
        self.init_ui()
        
        self.setAcceptDrops(True)
        self.show()  # Start visible
        self.raise_()  # Bring to front
        self.cloud_upload_enabled = self.settings.get("s3_enabled", False) # Load s3 enabled state
        self.cloud_upload_buttons = []  # Initialize buttons list
        print(f"settings: {self.settings}")
        print(f"Cloud upload enabled: {self.cloud_upload_enabled}")
        self.toggle_cloud_upload_button(self.cloud_upload_enabled) # Set initial button state
        
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
        
        # Make sure toggle button is in front
        self.update_toggle_button_position()
        
        # Fetch server files on initialization if S3 is enabled
        if self.cloud_upload_enabled:
            self.fetch_server_files()
            self.render_server_files()
    
    def init_ui(self):
        self.setWindowTitle("Dropp - File Shelf")
        self.set_window_flags(always_on_top=True)
        
        # Set background to semi-transparent dark color
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        # Set initial size for 1 file
        self.item_width = 80
        self.item_spacing = 10
        self.window_margin = 40
        initial_width = self.window_margin
        self.num_items = 0  # Initialize item count
        
        self.setFixedHeight(180)
        self.setMinimumWidth(initial_width)
        self.setWindowOpacity(0.95)
        
        # Animation properties
        self.animation = QPropertyAnimation(self, b"geometry")
        self.animation.setDuration(200)  # 200ms animation
        self.animation.setEasingCurve(QEasingCurve.Type.OutQuad)
        
        # Position at top-right near menu bar
        screen = QApplication.primaryScreen().availableGeometry()
        self.initial_x = screen.right() - initial_width
        self.move(self.initial_x, screen.top() + 40)
        
        # Setup central widget with background
        central_widget = QWidget()
        central_widget.setObjectName("centralWidget")
        central_widget.setStyleSheet("""        
            #centralWidget {
            }
        """)
        
        main_layout = QVBoxLayout(central_widget)
        
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
        
        scroll_area.setWidget(self.files_container)
        main_layout.addWidget(scroll_area)
        
        self.setCentralWidget(central_widget)
        self.update_window_width()
    
    def update_window_width(self):
        """
        Central method to update window width based on absolute metrics.
        Uses the number of items to calculate the appropriate width.
        """
        if not self.is_expanded:
            return self.collapsed_width
            
        # Calculate exact width needed based on the absolute number of items
        new_width = self.num_items * (self.item_width + self.item_spacing) + self.window_margin
        
        # Calculate position to maintain right edge alignment
        screen = QApplication.primaryScreen().availableGeometry()
        new_x = screen.right() - new_width
        
        # Animate both size and position
        self.animation.stop()
        new_geometry = self.geometry()
        new_geometry.setX(new_x)
        new_geometry.setRight(new_x + new_width)
        print(f"Screen width: {screen.width()}, new X: {new_x}, new width: {new_width}")
        self.animation.setStartValue(self.geometry())
        self.animation.setEndValue(new_geometry)
        self.animation.start()
        
        return new_width
    
    def toggle_expansion(self):
        """Toggle between expanded and collapsed state"""
        self.is_expanded = not self.is_expanded
        
        screen = QApplication.primaryScreen().availableGeometry()
        current_geometry = self.geometry()
        
        if self.is_expanded:
            # Expanding: calculate width based on items
            new_width = self.num_items * (self.item_width + self.item_spacing) + self.window_margin
            if new_width < self.minimumWidth():
                new_width = self.minimumWidth()
            new_x = screen.right() - new_width
        else:
            # Collapsing: use collapsed width
            new_width = self.collapsed_width
            new_x = screen.right() - new_width
        
        # Stop any running animations
        self.expansion_animation.stop()
        
        # Set up new geometry maintaining right edge alignment
        new_geometry = current_geometry
        new_geometry.setX(new_x)
        new_geometry.setRight(new_x + new_width)
        
        # Animate the transition
        self.expansion_animation.setStartValue(current_geometry)
        self.expansion_animation.setEndValue(new_geometry)
        self.expansion_animation.start()
        
        # Update toggle button position
        self.update_toggle_button_position()
    
    def resizeEvent(self, event):
        """Handle resize events to update toggle button position"""
        super().resizeEvent(event)
        self.update_toggle_button_position()
        
    def update_toggle_button_position(self):
        """Update the position of the toggle button on the left edge"""
        self.toggle_button.setGeometry(0, 0, self.toggle_button.width(), self.height())
        self.toggle_button.raise_()
    
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            self.showOverlay()
            # Auto-expand if window is collapsed
            if not self.is_expanded:
                self.toggle_expansion()
                self.toggle_button.expanded = True
                self.toggle_button.setToolTip("Click to hide shelf")
                self.toggle_button.update()
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
        # If shelf is collapsed, expand it first
        if not self.is_expanded:
            self.toggle_expansion()
        
        filename = os.path.basename(file_path)
        
        # Check if file already exists on shelf
        if filename in self.stored_files:
            # Find and return the existing file item
            for i in range(self.files_layout.count()):
                widget = self.files_layout.itemAt(i).widget()
                if isinstance(widget, FileItem) and widget.file_path == file_path:
                    return widget
            return None
        
        # Add file to storage
        self.stored_files.append(filename)
        
        # Create file item widget
        file_item = FileItem(file_path, parent=self)
        file_item.cloud_upload_button.setVisible(self.cloud_upload_enabled)
        self.cloud_upload_buttons.append(file_item.cloud_upload_button)
        file_item.remove_requested.connect(self.remove_file_from_shelf)
        file_item.file_dragged_out.connect(self.remove_file_from_shelf)
        file_item.cloud_upload_requested.connect(self.upload_file_to_s3)
        self.files_layout.addWidget(file_item)
        
        # Update item count and window width
        self.num_items += 1
        self.update_window_width()
        
        return file_item
    
    def remove_file_from_shelf(self, file_path):
        """Remove a file from the shelf"""
        # Find the file widget first to check its status
        print(f"Attempting to remove {file_path} from shelf...")
        file_widget = None
        for i in range(self.files_layout.count()):
            widget = self.files_layout.itemAt(i).widget()
            if isinstance(widget, FileItem) and widget.file_path == file_path:
                file_widget = widget
                break
        if file_widget != None:
            print(f"File widget found: {file_widget}")
        
        # If file has cloud status, delete from S3
        if file_widget and file_widget.status in ["cloud", "both", "mismatch"]:
            self.delete_file_from_s3(file_path, file_widget)
            print(f"Deleting cloud file: {file_widget} ({file_path})")
            
        print(f'noncloudfile for {file_widget}: {file_widget.file_path} found =[ {file_path} ] ...')
        # Clean now
        if file_path in self.stored_files:
            filename = os.path.basename(file_path)
            self.stored_files.remove(filename)
            
            # Find and remove the corresponding widget
            print(f"Widget count: {self.files_layout.count()}")
            for i in range(self.files_layout.count()):
                widget = self.files_layout.itemAt(i).widget()
                if isinstance(widget, FileItem) and widget.file_path == file_path:
                    print(f'deleting {widget} fromshelf')

                    widget.deleteLater()
                    self.files_layout.removeWidget(widget)
                    break

        print(f'noncloudfile for {file_widget}: {file_widget.file_path} found =[ {file_path} ] cleared ...')

        # Update item count and window width
        self.num_items -= 1
        self.update_window_width()
    
    def delete_file_from_s3(self, file_path, file_widget):
        """Delete a file from S3 bucket"""
        print(f"Deleting file from S3: {file_path}")
        s3_settings = self.load_settings()
        if not s3_settings.get("s3_enabled"):
            print("S3 is not enabled in settings.")
            return
        
        bucket_name = s3_settings.get("s3_bucket_name")
        access_key = s3_settings.get("aws_access_key")
        secret_key = s3_settings.get("aws_secret_key")
        region = s3_settings.get("aws_region")
        
        if not all([bucket_name, access_key, secret_key, region]):
            print("Missing S3 settings. Please check settings dialog.")
            return
        
        try:
            s3 = boto3.client('s3',
                            aws_access_key_id=access_key,
                            aws_secret_access_key=secret_key,
                            region_name=region,
                            endpoint_url=self.settings.get("s3_gateway_url") or None)
            
            # Get the file name for S3
            file_name = os.path.basename(file_path)
            
            # Delete the file from S3
            s3.delete_object(Bucket=bucket_name, Key=file_name)
            print(f"Successfully deleted {file_name} from S3 bucket {bucket_name}")
            
            # Update parent.server_files by removing the file
            if hasattr(self.parent, 'server_files') and file_name in self.parent.server_files:
                del self.parent.server_files[file_name]
                # Save updated server files to disk
                self.parent.flush_server_files()
                
        except Exception as e:
            print(f"Error deleting from S3: {e}")

    def paintEvent(self, event):
        """Custom paint event to create rounded corners and border on all sides except right"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        # Set the window background
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(50, 50, 50, 230))  # Semi-transparent light gray
        # painter.drawRoundedRect(self.rect(), 10, 10)
        
        # Draw border on all sides except right
        
        # Left border (not drawn when collapsed)
        if self.is_expanded:
            painter.drawLine(0, 10, 0, self.height() - 10)
        
        # Top border (with rounded corners)
        path = QPainterPath()
        path.moveTo(10, 0)
        path.lineTo(self.width() - 10, 0)
        painter.drawPath(path)
        
        # Bottom border (with rounded corners)
        path = QPainterPath()
        path.moveTo(10, self.height() - 1)
        path.lineTo(self.width() - 10, self.height() - 1)
        painter.drawPath(path)

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

    def fetch_server_files(self):
        """Fetch files from S3 bucket and store their information in parent.server_files"""
        if not hasattr(self.parent, 'server_files'):
            print("Parent doesn't have server_files attribute")
            return False
            
        s3_settings = self.load_settings()
        if not s3_settings.get("s3_enabled"):
            print("S3 is not enabled in settings.")
            self.parent.server_files = {}
            self.parent.flush_server_files()
            return False
            
        bucket_name = s3_settings.get("s3_bucket_name")
        access_key = s3_settings.get("aws_access_key")
        secret_key = s3_settings.get("aws_secret_key")
        region = s3_settings.get("aws_region")
        
        if not all([bucket_name, access_key, secret_key, region]):
            print("Missing S3 settings. Please check settings dialog.")
            self.parent.server_files = {}
            self.parent.flush_server_files()
            return False
            
        try:
            s3 = boto3.client('s3',
                            aws_access_key_id=access_key,
                            aws_secret_access_key=secret_key,
                            region_name=region,
                            endpoint_url=self.settings.get("s3_gateway_url") or None)
            
            print(f"Fetching files from S3 bucket: {bucket_name}")
            response = s3.list_objects_v2(Bucket=bucket_name)
            
            if 'Contents' in response:
                # Update parent.server_files with the latest information
                for obj in response['Contents']:
                    if obj['Key'] not in self.parent.server_files:
                        self.parent.server_files[obj['Key']] = {
                            'size': obj['Size'],
                            'local_path': None
                        }
                print(f"Fetched {len(self.parent.server_files)} files from S3")
                self.parent.flush_server_files()  # Save to disk
                return True
            else:
                print(f"No files found in S3 bucket: {bucket_name}")
                self.parent.server_files = {}
                self.parent.flush_server_files()  # Save to disk
                return True  # Successfully connected but no files
                
        except Exception as e:
            print(f"Error fetching files from S3: {e}")
            self.parent.server_files = {}
            self.parent.flush_server_files()  # Save to disk
            return False
    
    def render_server_files(self):
        """Render server files in the UI and update statuses using parent.server_files"""
        if not hasattr(self.parent, 'server_files') or not self.parent.server_files:
            print("No server files to render.")
            return
        
        print(f"Rendering {len(self.parent.server_files)} server files")
        print(f"Server files: {self.parent.server_files}")
        
        for s3_file, file_data in self.parent.server_files.items():
            local_path = file_data.get('local_path')
            s3_size = file_data.get('size')
            
            # If local_path is None, file only exists in S3
            file_item = self.add_file_to_shelf(s3_file)
            if local_path is None or not os.path.exists(local_path):
                # Update status to cloud-only
                file_item.update_file_status('cloud', s3_size)
            elif s3_size != os.path.getsize(local_path):
                # Update status to mismatch
                file_item.file_path = local_path
                file_item.update_file_status('mismatch', s3_size)
            else:
                # Update status to both
                file_item.file_path = local_path
                file_item.update_file_status('both', s3_size)
    
    def sync_from_s3(self):
        """Sync files from S3 bucket to shelf"""
        print("Syncing from S3...")
        s3_settings = self.load_settings()
        if not s3_settings.get("s3_enabled"):
            print("S3 sync is not enabled in settings.")
            return

        bucket_name = s3_settings.get("s3_bucket_name")
        access_key = s3_settings.get("aws_access_key")
        secret_key = s3_settings.get("aws_secret_key")
        region = s3_settings.get("aws_region")

        if not all([bucket_name, access_key, secret_key, region]):
            print("Missing S3 settings. Please check settings dialog.")
            return
        
        try:
            s3 = boto3.client('s3',
                              aws_access_key_id=access_key,
                              aws_secret_access_key=secret_key,
                              region_name=region,
                              endpoint_url=self.settings.get("s3_gateway_url") or None)
            print(f"Connecting to S3 bucket: {bucket_name}")
            response = s3.list_objects_v2(Bucket=bucket_name)
            print(f"Response from S3: {response}")
            if 'Contents' in response:
                # Update parent.server_files with the latest information
                for obj in response['Contents']:
                    if obj['Key'] not in self.parent.server_files:
                        self.parent.server_files[obj['Key']] = {
                            'size': obj['Size'],
                            'local_path': None
                        }
                print(f"Fetched {len(self.parent.server_files)} files from S3")
                print(f"Server files: {self.parent.server_files}")
                # Save updated server files to disk
                self.parent.flush_server_files()
                
                # Render the updated server files
                self.render_server_files()
            else:
                print(f"No files found in S3 bucket: {bucket_name}")
                self.parent.server_files = {}
                self.parent.flush_server_files()

        except Exception as e:
            print(f"Error syncing from S3: {e}")


    def contextMenuEvent(self, event):
        """Handle right-click context menu for the shelf window."""
        context_menu = QMenu(self)

        # Sync from S3 action
        sync_s3_action = context_menu.addAction("Sync from S3")
        sync_s3_action.triggered.connect(self.sync_from_s3)

        # Quit action
        quit_action = context_menu.addAction("Quit")
        quit_action.triggered.connect(QApplication.instance().quit)

        # Settings action
        settings_action = context_menu.addAction("Settings")
        settings_action.triggered.connect(self.open_settings_menu)

        context_menu.popup(self.mapToGlobal(event.pos()))

    def open_settings_menu(self):
        """Open the settings menu dialog."""
        dialog = SettingsDialog(self)
        if dialog.exec(): # Show as modal dialog and wait for result
            print("Settings dialog closed with OK") 
            # Refresh S3 state after settings change
            self.settings = self.load_settings()
            self.cloud_upload_enabled = self.settings.get("s3_enabled", False)
            self.toggle_cloud_upload_button(self.cloud_upload_enabled)
            
            # Fetch and render server files if S3 is enabled
            if self.cloud_upload_enabled:
                if self.fetch_server_files():
                    self.render_server_files()
        else:
            print("Settings dialog cancelled")


    def toggle_cloud_upload_button(self, enabled):
        """Toggle visibility of cloud upload buttons"""
        self.cloud_upload_enabled = enabled
        for button in self.cloud_upload_buttons:
            button.setVisible(enabled)
    
    def upload_file_to_s3(self, file_path):
        """Upload a file to S3 bucket and update its status"""
        print(f"Uploading file to S3: {file_path}")
        s3_settings = self.load_settings()
        if not s3_settings.get("s3_enabled"):
            print("S3 upload is not enabled in settings.")
            return
        
        bucket_name = s3_settings.get("s3_bucket_name")
        access_key = s3_settings.get("aws_access_key")
        secret_key = s3_settings.get("aws_secret_key")
        region = s3_settings.get("aws_region")
        
        if not all([bucket_name, access_key, secret_key, region]):
            print("Missing S3 settings. Please check settings dialog.")
            return
        
        try:
            s3 = boto3.client('s3',
                            aws_access_key_id=access_key,
                            aws_secret_access_key=secret_key,
                            region_name=region,
                            endpoint_url=self.settings.get("s3_gateway_url") or None)
            
            # Get the file name (key) for S3
            file_name = os.path.basename(file_path)
            # Calculate file size for Content-Length header
            file_size = os.path.getsize(file_path)
            print(f"Uploading file with size: {file_size} bytes")
            with open(file_path, 'rb') as f:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=file_name,
                    Body=f,
                    ContentLength=file_size,
                    ContentType='application/octet-stream'
                )

            print(f"Successfully uploaded {file_path} to S3 bucket {bucket_name}")

            # Get the file size of the uploaded file
            response = s3.head_object(Bucket=bucket_name, Key=file_name)
            cloud_size = response.get('ContentLength')
            
            # Update parent.server_files with the new file information
            self.parent.server_files[file_name] = {
                'size': cloud_size,
                'local_size': file_size,
                'local_path': file_path
            }
            # Save updated server files to disk
            self.parent.flush_server_files()
            
            # Find the file item and update its status
            for i in range(self.files_layout.count()):
                widget = self.files_layout.itemAt(i).widget()
                if isinstance(widget, FileItem) and widget.file_path == file_path:
                    local_size = calculate_size(file_path)
                    if local_size == cloud_size:
                        # Sizes match, set status to "both"
                        widget.update_file_status('both', cloud_size)
                    else:
                        # Sizes don't match, set status to "mismatch"
                        widget.update_file_status('mismatch', cloud_size)
                    break
            
        except Exception as e:
            print(f"Error uploading to S3: {e}")
    
    def load_settings(self):
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                return json.load(f)
        return {}