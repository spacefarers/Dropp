# Dropp - Persistent File Shelf

Dropp is a utility application that provides a persistent shelf for temporarily storing files that can be dragged between applications.

## Features

- Always-visible shelf that stays on top of other windows
- Drag and drop files onto the shelf to store them
- Drag files from the shelf directly to other applications
- System tray icon for easy access and control
- Semi-transparent interface that becomes fully visible during drag operations

## Requirements

- Python 3.6+
- PyQt6

## Installation

1. Clone this repository
2. Install the required dependencies:
   ```
   pip install PyQt6
   ```
3. Compile the resources:
   ```
   python compile_resources.py
   ```
4. Run the application:
   ```
   python main.py
   ```

## Usage

1. Launch the application
2. The shelf will appear at the top-right of your screen
3. Drag files from your file explorer onto the shelf to add them
4. Drag files from the shelf to other applications when needed
5. Click the system tray icon to show/hide the shelf
6. Right-click the system tray icon for additional options

## Platform Support

- Windows: Fully supported
- macOS: Supported (requires AppKit for proper integration)
- Linux: Supported (uses xcb platform plugin)

## License

This project is licensed under the MIT License - see the LICENSE file for details.