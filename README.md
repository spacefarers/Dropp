# Dropp - Persistent File Shelf

A utility for temporarily storing files that can be dragged between applications.

## Features

- System tray integration
- Drag and drop file storage
- Cloud storage integration with S3
- Cross-platform support (macOS and Windows)

## Building from Source

### Prerequisites

- Python 3.6+
- PyQt6
- PyInstaller
- boto3 (for S3 integration)

### Installation

1. Clone the repository
2. Install dependencies:

```bash
pip install -r requirements.txt
```

### Building the Application

#### Cross-Platform Build

The easiest way to build the application is to use the cross-platform build script:

```bash
python build.py
```

This script will detect your platform and run the appropriate build process.

#### Platform-Specific Builds

##### Building for macOS

To build the application specifically for macOS:

```bash
# Make the build script executable
chmod +x build_macos.sh

# Run the build script
./build_macos.sh
```

This will create a `Dropp.app` in the `dist` directory and a `Dropp.dmg` installer.

###### Requirements for DMG creation:
- `create-dmg` tool: `brew install create-dmg`

##### Building for Windows

To build the application specifically for Windows:

```bash
# Run the build script
build_windows.bat
```

This will create a `Dropp` directory in the `dist` directory with the application files.

###### Creating a Windows Installer

The Windows build script will attempt to create an installer if NSIS is installed:

1. Install NSIS: https://nsis.sourceforge.io/Download
2. Run the build script, which will automatically create `Dropp_Setup.exe`

## Usage

1. Launch the application
2. Drag files onto the shelf to store them
3. Drag files from the shelf to other applications
4. Right-click on the tray icon for additional options

## Configuration

S3 integration can be configured through the Settings menu:

1. Right-click on the shelf
2. Select "Settings"
3. Configure your S3 credentials and bucket information

## License

See the [LICENSE](LICENSE.txt) file for details.