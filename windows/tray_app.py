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

import json
import os
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


def create_icon_image(color: str = "green") -> Image.Image:
    """Create a simple tray icon."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    fill = (76, 175, 80, 255) if color == "green" else (66, 133, 244, 255)
    draw.rounded_rectangle([4, 4, 60, 60], radius=12, fill=fill)
    # Down arrow
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
        self._set_icon_color("blue")

        def on_complete(title, file_path, plat):
            self.downloads.insert(0, {"title": title, "path": file_path, "platform": plat})
            self._notify(f"Done: {title}")
            self._set_icon_color("green")

        def on_error(message):
            self._notify(f"Error: {message}")
            self._set_icon_color("green")

        download_media(url, platform, on_complete=on_complete, on_error=on_error)

    def _notify(self, message: str):
        if self.icon:
            try:
                self.icon.notify(message, "ClipGrab")
            except Exception:
                pass

    def _set_icon_color(self, color: str):
        if self.icon:
            self.icon.icon = create_icon_image(color)

    def _open_folder(self):
        os.startfile(str(DOWNLOAD_DIR))

    def _quit(self):
        self.monitor.stop()
        if self.icon:
            self.icon.stop()

    def run(self):
        menu = pystray.Menu(
            pystray.MenuItem("ClipGrab - Watching clipboard", None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Open Downloads Folder", lambda: self._open_folder()),
            pystray.MenuItem("Quit", lambda: self._quit()),
        )

        self.icon = pystray.Icon(
            "ClipGrab",
            create_icon_image("green"),
            "ClipGrab - Watching clipboard",
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
