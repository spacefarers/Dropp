#!/usr/bin/env python3
import os
import sys
from PIL import Image

def create_windows_ico():
    """Create Windows .ico file from shelf_icon.png"""
    try:
        from PIL import Image
    except ImportError:
        print("Error: Pillow library is required. Install with: pip install pillow")
        return False
    
    source_file = os.path.join("icons", "shelf_icon.png")
    target_file = os.path.join("icons", "dropp.ico")
    
    if not os.path.exists(source_file):
        print(f"Error: Source icon file not found: {source_file}")
        return False
    
    try:
        # Open the source image
        img = Image.open(source_file)
        
        # Create a list of sizes for the .ico file
        sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
        
        # Resize the image to all required sizes
        resized_images = []
        for size in sizes:
            resized_img = img.resize(size, Image.LANCZOS)
            resized_images.append(resized_img)
        
        # Save as .ico file
        resized_images[0].save(
            target_file,
            format="ICO",
            sizes=[(img.width, img.height) for img in resized_images],
            append_images=resized_images[1:]
        )
        
        print(f"Successfully created Windows icon: {target_file}")
        return True
    
    except Exception as e:
        print(f"Error creating Windows icon: {e}")
        return False

def create_macos_icns():
    """Create macOS .icns file from shelf_icon.png"""
    # This is more complex and requires macOS-specific tools
    # For now, we'll use the high-res PNG directly in the spec file
    print("Note: For macOS, we'll use the high-resolution PNG directly.")
    print("To create a proper .icns file, use the macOS iconutil tool.")
    return True

if __name__ == "__main__":
    print("Creating application icons...")
    
    # Create Windows .ico
    if sys.platform.startswith('win'):
        create_windows_ico()
    
    # Create macOS .icns (or use PNG directly)
    if sys.platform == 'darwin':
        create_macos_icns()
    
    print("Icon creation completed.")