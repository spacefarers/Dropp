import os
import subprocess
import sys

def compile_resources():
    """Compile the resources.qrc file into resources_rc.py using pyside6-rcc."""
    print("Compiling resources...")

    # Check if pyside6-rcc is available
    try:
        # Try to find pyside6-rcc in the system
        subprocess.run(
            ["pyside6-rcc", "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        compiler = "pyside6-rcc"
    except (subprocess.SubprocessError, FileNotFoundError):
        print("Error: Could not find PySide6 resource compiler (pyside6-rcc).")
        print("Please install PySide6 tools or make sure pyside6-rcc is in your PATH.")
        sys.exit(1)

    # Compile the resources.qrc file into resources_rc.py
    try:
        result = subprocess.run(
            [compiler, "resources.qrc", "-o", "resources_rc.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        print("Resources compiled successfully.")
    except subprocess.SubprocessError as e:
        print(f"Error compiling resources: {e}")
        print(f"Output: {e.stdout}")
        print(f"Error: {e.stderr}")
        sys.exit(1)

if __name__ == "__main__":
    compile_resources()
