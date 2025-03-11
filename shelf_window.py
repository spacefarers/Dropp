from PyQt6.QtWidgets import QMainWindow, QLabel, QVBoxLayout, QWidget
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QDragEnterEvent, QDropEvent

class ShelfWindow(QMainWindow):
    file_taken = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        self.init_ui()
        self.setAcceptDrops(True)

    def init_ui(self):
        self.setWindowTitle("Drag Shelf")
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(300, 200)
        self.setWindowOpacity(0.9)

        # Setup central widget
        central_widget = QWidget()
        layout = QVBoxLayout()
        
        self.drop_label = QLabel("Drop files here")
        self.drop_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.drop_label)
        
        central_widget.setLayout(layout)
        self.setCentralWidget(central_widget)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
            self.setWindowOpacity(1.0)

    def dropEvent(self, event: QDropEvent):
        urls = event.mimeData().urls()
        if urls:
            file_path = urls[0].toLocalFile()
            self.file_taken.emit(file_path)
            self.hide()
