#!/bin/bash
set -e

echo "Building Dropp for macOS..."

# Create application icons
python create_icons.py

# Ensure PyQt resources are compiled
python compile_resources.py

# Clean previous build
rm -rf build dist

# Build the app using PyInstaller
pyinstaller dropp.spec

# Create a DMG file
echo "Creating DMG file..."
create-dmg \
  --volname "Dropp" \
  --volicon "icons/shelf_icon.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Dropp.app" 175 190 \
  --hide-extension "Dropp.app" \
  --app-drop-link 425 190 \
  "Dropp.dmg" \
  "dist/Dropp.app"

echo "Build completed successfully!"
echo "DMG file created at: Dropp.dmg"