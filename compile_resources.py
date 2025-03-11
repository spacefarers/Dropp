import os
import subprocess
import sys

def compile_resources():
    """Compile the resources.qrc file into resources.rcc"""
    print("Compiling resources...")
    
    # Check if pyrcc6 is available
    try:
        # Try to find pyrcc6 in the system
        subprocess.run(["pyrcc6", "--version"], 
                      stdout=subprocess.PIPE, 
                      stderr=subprocess.PIPE, 
                      check=True)
        compiler = "pyrcc6"
    except (subprocess.SubprocessError, FileNotFoundError):
        # If pyrcc6 is not found, try to use the PyQt6 module
        try:
            import PyQt6
            pyqt_dir = os.path.dirname(PyQt6.__file__)
            compiler = os.path.join(pyqt_dir, "bindings", "pyrcc6")
            if not os.path.exists(compiler):
                # On Windows, it might be in a different location
                compiler = os.path.join(pyqt_dir, "Qt6", "bin", "rcc.exe")
                if not os.path.exists(compiler):
                    raise FileNotFoundError("Could not find pyrcc6 or rcc.exe")
        except (ImportError, FileNotFoundError):
            print("Error: Could not find PyQt6 resource compiler (pyrcc6).")
            print("Please install PyQt6 tools or make sure pyrcc6 is in your PATH.")
            sys.exit(1)
    
    # Compile the resources
    try:
        if compiler.endswith("rcc.exe"):
            # Using Qt's rcc directly
            result = subprocess.run(
                [compiler, "-o", "resources_rc.py", "resources.qrc"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True
            )
        else:
            # Using pyrcc6
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