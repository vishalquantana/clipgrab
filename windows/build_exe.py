"""
Build script for ClipGrab Windows .exe

Usage:
    pip install pyinstaller pystray Pillow pyperclip
    python build_exe.py

Output:
    dist/ClipGrab.exe — standalone executable
"""

import PyInstaller.__main__
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
engine_path = os.path.join(script_dir, "..", "engine", "download_manager.py")

PyInstaller.__main__.run([
    os.path.join(script_dir, "tray_app.py"),
    "--name", "ClipGrab",
    "--onefile",
    "--windowed",
    "--add-data", f"{engine_path};engine",
    "--icon", os.path.join(script_dir, "icon.ico") if os.path.exists(os.path.join(script_dir, "icon.ico")) else "NONE",
    "--clean",
    "--noconfirm",
])
