#!/usr/bin/env python3
import os
import sys
import subprocess
import platform

def main():
    """
    Cross-platform build script for Dropp application.
    Detects the platform and runs the appropriate build script.
    """
    print("Dropp Application Builder")
    print("========================")
    
    # Detect platform
    system = platform.system()
    print(f"Detected platform: {system}")
    
    # Create icons
    print("\nCreating application icons...")
    subprocess.run([sys.executable, "create_icons.py"], check=True)
    
    # Compile resources
    print("\nCompiling resources...")
    subprocess.run([sys.executable, "compile_resources.py"], check=True)
    
    # Build application
    print("\nBuilding application...")
    
    if system == "Darwin":  # macOS
        print("Building for macOS...")
        # Make build script executable
        os.chmod("build_macos.sh", 0o755)
        # Run macOS build script
        subprocess.run(["./build_macos.sh"], check=True)
        
    elif system == "Windows":  # Windows
        print("Building for Windows...")
        # Run Windows build script
        subprocess.run(["build_windows.bat"], shell=True, check=True)
        
    else:  # Linux or other
        print("Building for Linux/other...")
        # Use PyInstaller directly
        subprocess.run([
            "pyinstaller",
            "--name=Dropp",
            "--icon=icons/shelf_icon.png",
            "--windowed",
            "--add-data=icons/*.png:icons",
            "main.py"
        ], check=True)
    
    print("\nBuild completed successfully!")
    print("Check the 'dist' directory for the packaged application.")

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"\nError: Build failed with error code {e.returncode}")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)