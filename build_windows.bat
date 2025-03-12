@echo off
echo Building Dropp for Windows...

REM Create application icons
python create_icons.py

REM Ensure PyQt resources are compiled
python compile_resources.py

REM Clean previous build
rmdir /s /q build dist
del /q Dropp.spec

REM Build the app using PyInstaller
pyinstaller dropp.spec

REM Create installer using NSIS (if installed)
if exist "C:\Program Files (x86)\NSIS\makensis.exe" (
    echo Creating Windows installer...
    "C:\Program Files (x86)\NSIS\makensis.exe" windows_installer.nsi
    echo Installer created at: Dropp_Setup.exe
) else (
    echo NSIS not found. Skipping installer creation.
    echo You can manually create an installer using the files in dist\Dropp
)

echo Build completed successfully!