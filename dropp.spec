# -*- mode: python ; coding: utf-8 -*-
import sys
import os

block_cipher = None

# Determine platform-specific settings
is_mac = sys.platform == 'darwin'
is_windows = sys.platform.startswith('win')

# Common data files
datas = [
    ('icons/*.png', 'icons'),
]

# Platform-specific settings
if is_mac:
    icon = 'icons/shelf_icon.png'  # macOS can use PNG directly
    console = False
    name = 'Dropp'
elif is_windows:
    icon = 'icons/dropp.ico'  # Windows needs .ico file
    console = False
    name = 'Dropp'
else:  # Linux or other
    icon = 'icons/shelf_icon.png'
    console = False
    name = 'Dropp'

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=['PyQt6.sip'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=console,
    disable_windowed_traceback=False,
    argv_emulation=is_mac,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name=name,
)

if is_mac:
    app = BUNDLE(
        coll,
        name='Dropp.app',
        icon=icon,
        bundle_identifier='com.dropp.app',
        info_plist={
            'CFBundleShortVersionString': '1.0.0',
            'CFBundleVersion': '1.0.0',
            'NSHighResolutionCapable': True,
            'LSUIElement': True,  # Makes the app a background app without dock icon
            'CFBundleDisplayName': 'Dropp',
            'CFBundleName': 'Dropp',
            'NSHumanReadableCopyright': '© 2025',
            'LSApplicationCategoryType': 'public.app-category.utilities',
        },
    )