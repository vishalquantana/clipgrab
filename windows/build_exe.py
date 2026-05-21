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
icon_path = os.path.join(script_dir, "icon.ico")

args = [
    os.path.join(script_dir, "tray_app.py"),
    "--name", "ClipGrab",
    "--onefile",
    "--windowed",
    "--add-data", f"{engine_path};engine",
    "--add-data", f"{icon_path};.",  # Bundle icon.ico so notifications use it
    "--clean",
    "--noconfirm",
]

if os.path.exists(icon_path):
    args += ["--icon", icon_path]

PyInstaller.__main__.run(args)
