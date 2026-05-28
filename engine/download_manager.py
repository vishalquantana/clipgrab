#!/usr/bin/env python3
"""
ClipGrab Download Engine
========================
Downloads media from social media URLs using yt-dlp (primary) with
cobalt.tools API as a fallback.

Usage:
    python download_manager.py <URL> --output-dir <DIR>

Output protocol (each line is a JSON object):
    {"type": "progress", "percent": N, "downloaded_bytes": N, "total_bytes": N, "eta_seconds": N}
    {"type": "complete", "file_path": "...", "title": "...", "platform": "...",
     "media_type": "video|image", "file_size": N, "thumbnail_path": "..."}
    {"type": "error", "message": "...", "code": "..."}

Exit codes:
    0  success
    1  error (JSON error line already emitted)
    2  argument parsing error (argparse default)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# JSON output helpers
# ---------------------------------------------------------------------------

def emit(obj: dict) -> None:
    """Write a JSON line to stdout and flush immediately."""
    print(json.dumps(obj), flush=True)


def emit_error(message: str, code: str) -> None:
    emit({"type": "error", "message": message, "code": code})


def die(message: str, code: str, exit_code: int = 1) -> None:
    emit_error(message, code)
    sys.exit(exit_code)


# ---------------------------------------------------------------------------
# URL validation & platform detection
# ---------------------------------------------------------------------------

PLATFORM_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("instagram", re.compile(
        r"instagram\.com/p/|instagram\.com/reels?/|instagram\.com/stories/",
        re.IGNORECASE,
    )),
    ("youtube", re.compile(
        r"youtube\.com/watch|youtu\.be/|youtube\.com/shorts/",
        re.IGNORECASE,
    )),
    ("tiktok", re.compile(
        r"tiktok\.com/.+/video/|tiktok\.com/@.+|vm\.tiktok\.com/",
        re.IGNORECASE,
    )),
    ("twitter", re.compile(
        r"twitter\.com/.+/status/|x\.com/.+/status/",
        re.IGNORECASE,
    )),
    ("reddit", re.compile(
        r"reddit\.com/r/.+/comments/|redd\.it/",
        re.IGNORECASE,
    )),
    ("facebook", re.compile(
        r"facebook\.com/.+/videos/|facebook\.com/watch|fb\.watch/|facebook\.com/reel/",
        re.IGNORECASE,
    )),
    ("threads", re.compile(
        r"threads\.net/@.+/post/",
        re.IGNORECASE,
    )),
    ("vimeo", re.compile(
        r"vimeo\.com/\d+",
        re.IGNORECASE,
    )),
    ("pinterest", re.compile(
        r"pinterest\.com/pin/",
        re.IGNORECASE,
    )),
    ("twitch", re.compile(
        r"clips\.twitch\.tv/|twitch\.tv/.+/clip/",
        re.IGNORECASE,
    )),
    ("linkedin", re.compile(
        r"linkedin\.com/posts/|linkedin\.com/feed/update/",
        re.IGNORECASE,
    )),
]


def validate_url(url: str) -> None:
    if not url:
        die("URL must not be empty.", "INVALID_URL")
    if not url.startswith("http"):
        die(f"URL must start with 'http'. Got: {url!r}", "INVALID_URL")


def detect_platform(url: str) -> str:
    for platform, pattern in PLATFORM_PATTERNS:
        if pattern.search(url):
            return platform
    return "unknown"


# ---------------------------------------------------------------------------
# Path & dependency helpers
# ---------------------------------------------------------------------------

def _ensure_path() -> None:
    """Ensure Homebrew paths are in PATH (not always set in app sandbox)."""
    extra_paths = ["/opt/homebrew/bin", "/usr/local/bin"]
    current = os.environ.get("PATH", "")
    for p in extra_paths:
        if p not in current:
            current = p + ":" + current
    os.environ["PATH"] = current


def _find_ytdlp() -> Optional[str]:
    home = os.path.expanduser("~")
    candidates = [
        os.path.join(home, ".local", "bin", "yt-dlp"),
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
    ]
    if sys.platform == "win32":
        # Windows: yt-dlp installed via pip lands in Scripts/
        candidates = [
            os.path.join(home, "AppData", "Local", "Programs", "Python", "Scripts", "yt-dlp.exe"),
            os.path.join(sys.prefix, "Scripts", "yt-dlp.exe"),
            os.path.join(home, ".local", "bin", "yt-dlp.exe"),
        ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return shutil.which("yt-dlp")


def check_dependencies() -> None:
    _ensure_path()
    # yt-dlp is optional now (cobalt fallback exists), but ffmpeg is still needed
    if shutil.which("ffmpeg") is None and not _find_ytdlp():
        die(
            "Neither yt-dlp nor ffmpeg found in PATH. Install them and try again.",
            "MISSING_DEPENDENCY",
        )


# ---------------------------------------------------------------------------
# yt-dlp progress parsing
# ---------------------------------------------------------------------------

def _parse_progress_line(raw: str) -> Optional[dict]:
    raw = raw.strip()
    if not raw.startswith("{"):
        return None
    try:
        d = json.loads(raw)
    except json.JSONDecodeError:
        return None

    status = d.get("status", "")
    if status != "downloading":
        return None

    def _safe_float(key: str) -> float:
        v = d.get(key)
        if v is None or v == "NA" or v == "None" or v == "":
            return 0.0
        try:
            return float(v)
        except (TypeError, ValueError):
            return 0.0

    percent_str = d.get("_percent_str", "0%").strip().replace("%", "")
    try:
        percent = float(percent_str)
    except ValueError:
        percent = 0.0

    return {
        "type": "progress",
        "percent": round(percent, 1),
        "downloaded_bytes": int(_safe_float("downloaded_bytes")),
        "total_bytes": int(_safe_float("total_bytes") or _safe_float("total_bytes_estimate")),
        "eta_seconds": int(_safe_float("eta")),
    }


# ---------------------------------------------------------------------------
# Thumbnail handling
# ---------------------------------------------------------------------------

def _move_thumbnail(output_dir: Path, stem: str) -> Optional[str]:
    thumbs_dir = output_dir / ".thumbs"
    for ext in ("jpg", "jpeg", "png", "webp"):
        src = output_dir / f"{stem}.{ext}"
        if src.exists():
            thumbs_dir.mkdir(exist_ok=True)
            dst = thumbs_dir / src.name
            shutil.move(str(src), str(dst))
            return str(dst)
    return None


# ---------------------------------------------------------------------------
# Direct API fallbacks (no third-party services)
# ---------------------------------------------------------------------------

def _download_file(download_url: str, output_path: Path) -> bool:
    """Download a file from a URL with progress reporting."""
    try:
        req = urllib.request.Request(download_url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        })
        with urllib.request.urlopen(req, timeout=300) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            with open(output_path, "wb") as f:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = round(downloaded / total * 100, 1)
                        emit({
                            "type": "progress",
                            "percent": pct,
                            "downloaded_bytes": downloaded,
                            "total_bytes": total,
                            "eta_seconds": 0,
                        })
    except (urllib.error.URLError, TimeoutError) as e:
        output_path.unlink(missing_ok=True)
        return False

    return output_path.exists() and output_path.stat().st_size > 0


def _download_twitter_direct(url: str, output_dir: Path) -> bool:
    """
    Download Twitter/X video using the public syndication API.
    No auth required — uses the same API that tweet embeds use.
    """
    # Extract tweet ID from URL
    match = re.search(r"/status/(\d+)", url)
    if not match:
        return False

    tweet_id = match.group(1)
    api_url = f"https://cdn.syndication.twimg.com/tweet-result?id={tweet_id}&token=0"

    emit({"type": "progress", "percent": 5, "downloaded_bytes": 0, "total_bytes": 0, "eta_seconds": 0})

    try:
        req = urllib.request.Request(api_url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, TimeoutError):
        return False

    # Find the best video variant
    best_url = None
    best_bitrate = 0
    title = data.get("text", "twitter_video")[:80]
    # Clean title for filename
    title = re.sub(r'[<>:"/\\|?*\n\r]', ' ', title).strip()
    title = re.sub(r'\s+', ' ', title)
    thumbnail_url = None

    for media in data.get("mediaDetails", []):
        if media.get("type") != "video":
            continue
        thumbnail_url = media.get("media_url_https")
        for variant in media.get("video_info", {}).get("variants", []):
            if variant.get("content_type") != "video/mp4":
                continue
            bitrate = variant.get("bitrate", 0)
            if bitrate > best_bitrate:
                best_bitrate = bitrate
                best_url = variant.get("url")

    if not best_url:
        return False

    emit({"type": "progress", "percent": 10, "downloaded_bytes": 0, "total_bytes": 0, "eta_seconds": 0})

    # Download video
    filename = f"{title}_{tweet_id}.mp4"
    filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
    output_path = output_dir / filename

    if not _download_file(best_url, output_path):
        return False

    # Download thumbnail
    thumb_path = ""
    if thumbnail_url:
        thumbs_dir = output_dir / ".thumbs"
        thumbs_dir.mkdir(exist_ok=True)
        thumb_file = thumbs_dir / f"{output_path.stem}.jpg"
        try:
            urllib.request.urlretrieve(thumbnail_url, str(thumb_file))
            thumb_path = str(thumb_file)
        except Exception:
            pass

    emit({
        "type": "complete",
        "file_path": str(output_path),
        "title": title,
        "platform": "twitter",
        "media_type": "video",
        "file_size": output_path.stat().st_size,
        "thumbnail_path": thumb_path,
    })
    return True


# ---------------------------------------------------------------------------
# yt-dlp download
# ---------------------------------------------------------------------------

def _download_via_ytdlp(url: str, output_dir: Path, platform: str, existing_files: set, quality: str = "best") -> bool:
    """
    Try downloading via yt-dlp.
    Returns True if successful, False otherwise.
    """
    output_template = str(output_dir / "%(title).80s_%(id)s.%(ext)s")

    progress_template = (
        '{"status":"%(progress.status)s",'
        '"_percent_str":"%(progress._percent_str)s",'
        '"downloaded_bytes":"%(progress.downloaded_bytes)s",'
        '"total_bytes":"%(progress.total_bytes)s",'
        '"total_bytes_estimate":"%(progress.total_bytes_estimate)s",'
        '"eta":"%(progress.eta)s"}'
    )

    ytdlp_args = [
        "--write-thumbnail",
        "--convert-thumbnails", "jpg",
        "--newline",
        "--progress-template", progress_template,
        "--output", output_template,
    ]

    if quality == "audio":
        ytdlp_args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
    else:
        ytdlp_args += ["--merge-output-format", "mp4"]
        if quality == "1080":
            ytdlp_args += ["-f", "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"]
        elif quality == "720":
            ytdlp_args += ["-f", "bestvideo[height<=720]+bestaudio/best[height<=720]/best"]

    # Help yt-dlp find ffmpeg
    ffmpeg_bin = shutil.which("ffmpeg")
    if not ffmpeg_bin:
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]:
            if os.path.isfile(p):
                ffmpeg_bin = p
                break
    if ffmpeg_bin:
        ytdlp_args += ["--ffmpeg-location", ffmpeg_bin]

    ytdlp_args.append(url)

    ytdlp_bin = _find_ytdlp()
    if not ytdlp_bin:
        return False

    cmd = [ytdlp_bin] + ytdlp_args

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return False

    assert proc.stdout is not None
    stderr_lines: list[str] = []

    # Extract video ID from URL for fallback file matching
    video_id = ""
    id_match = re.search(r"[?&]v=([^&]+)|/shorts/([^?&/]+)|youtu\.be/([^?&/]+)|/video/(\d+)|/status/(\d+)|/p/([^/?]+)|/reel[s]?/([^/?]+)", url)
    if id_match:
        video_id = next((g for g in id_match.groups() if g), "")

    for raw_line in proc.stdout:
        progress = _parse_progress_line(raw_line)
        if progress:
            emit(progress)

    if proc.stderr:
        stderr_lines = proc.stderr.readlines()

    proc.wait()

    # Find the downloaded file — check new files first, then fall back to
    # matching by video ID (yt-dlp may skip download if file already exists)
    new_files = set(output_dir.iterdir()) - existing_files
    downloaded_file: Optional[Path] = None

    video_exts = (".mp4", ".mkv", ".webm", ".mov")
    image_exts = (".jpg", ".jpeg", ".png", ".gif")
    audio_exts = (".mp3", ".m4a", ".opus", ".aac", ".wav")

    # yt-dlp leaves per-format fragment files (e.g. "Title.f251.webm") when it
    # downloads separate video/audio streams but cannot merge them — which
    # happens when ffmpeg is missing or broken. These are not usable output.
    fragment_re = re.compile(r"\.f\d+\.[^.]+$", re.IGNORECASE)
    new_fragments = [f for f in new_files if f.is_file() and fragment_re.search(f.name)]
    selectable = [f for f in new_files if f not in new_fragments]

    # Search order depends on quality: audio downloads look for audio files first.
    if quality == "audio":
        ext_order = (audio_exts, video_exts, image_exts)
    else:
        ext_order = (video_exts, image_exts, audio_exts)

    # 1. Check newly created files (ignoring unmerged fragments)
    for exts in ext_order:
        for candidate in sorted(selectable):
            if candidate.is_file() and candidate.suffix.lower() in exts:
                downloaded_file = candidate
                break
        if downloaded_file is not None:
            break

    # 2. Fall back: find existing file matching the video ID
    if downloaded_file is None and video_id:
        match_exts = audio_exts if quality == "audio" else video_exts
        for candidate in sorted(output_dir.iterdir()):
            if (candidate.is_file() and video_id in candidate.name
                    and candidate.suffix.lower() in match_exts
                    and not fragment_re.search(candidate.name)):
                downloaded_file = candidate
                break

    # Guard: ffmpeg merge failed — only leftover fragments, no usable output.
    if downloaded_file is None and new_fragments:
        die(
            "ffmpeg could not merge the video and audio streams. Make sure ffmpeg "
            "is installed and working (try: brew reinstall ffmpeg).",
            "FFMPEG_MERGE_FAILED",
        )

    if downloaded_file is None:
        return False

    suffix = downloaded_file.suffix.lower()

    # Guard: audio-only was requested but ffmpeg did not produce an MP3.
    if quality == "audio" and suffix != ".mp3":
        die(
            "ffmpeg could not convert the audio to MP3. Make sure ffmpeg is "
            "installed and working (try: brew reinstall ffmpeg).",
            "FFMPEG_AUDIO_FAILED",
        )

    if suffix in audio_exts:
        media_type = "audio"
    elif suffix in image_exts:
        media_type = "image"
    else:
        media_type = "video"
    thumbnail_path = _move_thumbnail(output_dir, downloaded_file.stem)

    emit({
        "type": "complete",
        "file_path": str(downloaded_file),
        "title": downloaded_file.stem,
        "platform": platform,
        "media_type": media_type,
        "file_size": downloaded_file.stat().st_size,
        "thumbnail_path": thumbnail_path or "",
    })
    return True


# ---------------------------------------------------------------------------
# Main download routine (tries yt-dlp first, then cobalt)
# ---------------------------------------------------------------------------

def download(url: str, output_dir: Path, platform: str, quality: str = "best") -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    existing_files = set(output_dir.iterdir())

    # For Twitter/X, try the syndication API first (yt-dlp hangs on guest token).
    # The syndication path always returns best-quality mp4 and ignores `quality`.
    if platform == "twitter":
        success = _download_twitter_direct(url, output_dir)
        if success:
            return

    # Try yt-dlp
    if _find_ytdlp():
        success = _download_via_ytdlp(url, output_dir, platform, existing_files, quality)
        if success:
            return

    die("Download failed. yt-dlp could not process this URL.", "ALL_METHODS_FAILED")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ClipGrab download engine — yt-dlp + cobalt.tools fallback.",
    )
    parser.add_argument("url", help="URL to download")
    parser.add_argument("--output-dir", required=True, help="Directory to save downloads")
    parser.add_argument(
        "--quality",
        choices=["best", "1080", "720", "audio"],
        default="best",
        help="Download quality: best, 1080, 720, or audio (MP3)",
    )
    args = parser.parse_args()

    url: str = args.url
    output_dir = Path(args.output_dir)

    validate_url(url)
    platform = detect_platform(url)
    _ensure_path()
    download(url, output_dir, platform, args.quality)


if __name__ == "__main__":
    main()
