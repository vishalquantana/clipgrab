"""
ClipGrab — Windows System Tray App
===================================
Monitors the clipboard for social media URLs and downloads media using
the shared download engine.

Requirements:
    pip install pystray Pillow pyperclip

Usage:
    python tray_app.py
"""

from __future__ import annotations

import ctypes
import json
import os
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

try:
    import pystray
    from PIL import Image, ImageDraw
    import pyperclip
except ImportError:
    print("Missing dependencies. Install them with:")
    print("  pip install pystray Pillow pyperclip")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

DOWNLOAD_DIR = Path.home() / "Downloads" / "ClipGrab"
POLL_INTERVAL = 1.5  # seconds

# Support both running from source and as a PyInstaller bundle
if getattr(sys, "frozen", False):
    _base = Path(sys._MEIPASS)
    ENGINE_PATH = _base / "engine" / "download_manager.py"
else:
    ENGINE_PATH = Path(__file__).resolve().parent.parent / "engine" / "download_manager.py"

PLATFORM_PATTERNS = [
    ("Instagram", ["instagram.com/p/", "instagram.com/reel", "instagram.com/stories/"]),
    ("YouTube", ["youtube.com/watch", "youtu.be/", "youtube.com/shorts/"]),
    ("TikTok", ["tiktok.com/", "vm.tiktok.com/"]),
    ("Twitter/X", ["twitter.com/", "x.com/"]),
    ("Reddit", ["reddit.com/r/", "redd.it/"]),
    ("Facebook", ["facebook.com/", "fb.watch/"]),
    ("Threads", ["threads.net/"]),
    ("Vimeo", ["vimeo.com/"]),
    ("Pinterest", ["pinterest.com/pin/"]),
    ("Twitch", ["twitch.tv/"]),
    ("LinkedIn", ["linkedin.com/posts/", "linkedin.com/feed/update/"]),
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def detect_platform(url: str) -> str | None:
    lower = url.lower()
    for name, patterns in PLATFORM_PATTERNS:
        for p in patterns:
            if p in lower:
                return name
    return None


def copy_file_to_clipboard(file_path: str) -> bool:
    """Copy a file to the Windows clipboard so it can be pasted in apps."""
    try:
        import ctypes.wintypes

        CF_HDROP = 15
        GHND = 0x0042

        path = os.path.abspath(file_path)
        # DROPFILES struct: 20 bytes header + wide-char file path + double null
        path_wide = path.encode("utf-16-le") + b"\x00\x00"  # null-terminated
        header = struct.pack("IIIIi", 20, 0, 0, 0, 1)  # pFiles=20, pt=(0,0), fNC=0, fWide=1
        data = header + path_wide + b"\x00\x00"  # extra null for end of list

        kernel32 = ctypes.windll.kernel32
        user32 = ctypes.windll.user32

        hmem = kernel32.GlobalAlloc(GHND, len(data))
        if not hmem:
            return False
        ptr = kernel32.GlobalLock(hmem)
        ctypes.memmove(ptr, data, len(data))
        kernel32.GlobalUnlock(hmem)

        user32.OpenClipboard(None)
        user32.EmptyClipboard()
        user32.SetClipboardData(CF_HDROP, hmem)
        user32.CloseClipboard()
        return True
    except Exception:
        return False


def _icon_path() -> Path:
    """Resolve the path to icon.ico (works for source and PyInstaller)."""
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS) / "icon.ico"
    return Path(__file__).resolve().parent / "icon.ico"


def load_icon_image() -> Image.Image:
    """Load the ClipGrab .ico file, falling back to a generated icon."""
    ico = _icon_path()
    if ico.exists():
        try:
            return Image.open(str(ico))
        except Exception:
            pass
    # Fallback: generate a simple icon
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([4, 4, 60, 60], radius=12, fill=(76, 175, 80, 255))
    draw.polygon([(24, 22), (40, 22), (40, 38), (48, 38), (32, 52), (16, 38), (24, 38)], fill="white")
    return img


# ---------------------------------------------------------------------------
# Clipboard Monitor
# ---------------------------------------------------------------------------

class ClipboardMonitor:
    def __init__(self, on_url_detected):
        self.on_url_detected = on_url_detected
        self.processed_urls: set[str] = set()
        self.last_clipboard = ""
        self.running = False

    def start(self):
        self.running = True
        thread = threading.Thread(target=self._poll_loop, daemon=True)
        thread.start()

    def stop(self):
        self.running = False

    def _poll_loop(self):
        while self.running:
            try:
                text = pyperclip.paste()
                if text and text != self.last_clipboard:
                    self.last_clipboard = text
                    url = text.strip().split()[0] if text.strip() else ""
                    if url.startswith("http") and url not in self.processed_urls:
                        platform = detect_platform(url)
                        if platform:
                            self.processed_urls.add(url)
                            self.on_url_detected(url, platform)
            except Exception:
                pass
            time.sleep(POLL_INTERVAL)


# ---------------------------------------------------------------------------
# Download Manager
# ---------------------------------------------------------------------------

def download_media(url: str, platform: str, on_complete=None, on_error=None):
    """Run the download engine as a subprocess."""
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

    def _run():
        try:
            proc = subprocess.run(
                [sys.executable, str(ENGINE_PATH), url, "--output-dir", str(DOWNLOAD_DIR)],
                capture_output=True,
                text=True,
                timeout=300,
            )

            for line in proc.stdout.strip().split("\n"):
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if msg.get("type") == "complete":
                    file_path = msg.get("file_path", "")
                    title = msg.get("title", "Unknown")
                    if on_complete:
                        on_complete(title, file_path, platform)
                    return
                elif msg.get("type") == "error":
                    if on_error:
                        on_error(msg.get("message", "Unknown error"))
                    return

            if proc.returncode != 0:
                if on_error:
                    on_error(f"Download failed (exit code {proc.returncode})")

        except subprocess.TimeoutExpired:
            if on_error:
                on_error("Download timed out after 5 minutes")
        except Exception as e:
            if on_error:
                on_error(str(e))

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()


# ---------------------------------------------------------------------------
# Tray App
# ---------------------------------------------------------------------------

class ClipGrabTray:
    def __init__(self):
        self.icon: pystray.Icon | None = None
        self.monitor = ClipboardMonitor(on_url_detected=self._on_url_detected)
        self.downloads: list[dict] = []

    def _on_url_detected(self, url: str, platform: str):
        self._notify(f"Downloading from {platform}...")

        def on_complete(title, file_path, plat):
            self.downloads.insert(0, {"title": title, "path": file_path, "platform": plat})
            if file_path and copy_file_to_clipboard(file_path):
                self._notify(f"Done: {title}\nCopied to clipboard — paste anywhere!")
            else:
                self._notify(f"Done: {title}")

        def on_error(message):
            self._notify(f"Error: {message}")

        download_media(url, platform, on_complete=on_complete, on_error=on_error)

    def _notify(self, message: str):
        if self.icon:
            try:
                self.icon.notify(message, "ClipGrab by Quantana")
            except Exception:
                pass

    def _open_folder(self):
        os.startfile(str(DOWNLOAD_DIR))

    def _quit(self):
        self.monitor.stop()
        if self.icon:
            self.icon.stop()

    def run(self):
        menu = pystray.Menu(
            pystray.MenuItem("ClipGrab by Quantana", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Open Downloads Folder", lambda: self._open_folder()),
            pystray.MenuItem("Quit", lambda: self._quit()),
        )

        self.icon = pystray.Icon(
            "ClipGrab",
            load_icon_image(),
            "ClipGrab by Quantana",
            menu,
        )

        self.monitor.start()
        self.icon.run()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("ClipGrab for Windows — running in system tray")
    print(f"Downloads: {DOWNLOAD_DIR}")
    print("Copy a social media URL to start downloading.")
    app = ClipGrabTray()
    app.run()
