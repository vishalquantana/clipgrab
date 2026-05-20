#!/usr/bin/env python3
"""
ClipGrab Download Engine
========================
Wraps yt-dlp and emits newline-delimited JSON to stdout.

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
    """Raise SystemExit (via die) if the URL is not acceptable."""
    if not url:
        die("URL must not be empty.", "INVALID_URL")
    if not url.startswith("http"):
        die(f"URL must start with 'http'. Got: {url!r}", "INVALID_URL")


def detect_platform(url: str) -> str:
    """Return the platform name or 'unknown'."""
    for platform, pattern in PLATFORM_PATTERNS:
        if pattern.search(url):
            return platform
    return "unknown"


# ---------------------------------------------------------------------------
# Dependency checks
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
    """Find yt-dlp binary, preferring pipx and user-local installs."""
    home = os.path.expanduser("~")
    candidates = [
        os.path.join(home, ".local", "bin", "yt-dlp"),
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
    ]
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return shutil.which("yt-dlp")


def check_dependencies() -> None:
    _ensure_path()
    missing = []
    if shutil.which("yt-dlp") is None:
        missing.append("yt-dlp")
    if shutil.which("ffmpeg") is None:
        missing.append("ffmpeg")
    if missing:
        die(
            f"Required tools not found in PATH: {', '.join(missing)}. "
            "Install them and try again.",
            "MISSING_DEPENDENCY",
        )


# ---------------------------------------------------------------------------
# yt-dlp progress parsing
# ---------------------------------------------------------------------------

def _parse_progress_line(raw: str) -> Optional[dict]:
    """
    yt-dlp --progress-template outputs lines like:
        {"status":"downloading","_percent_str":" 12.3%","downloaded_bytes":...}

    We normalise to our own schema.
    """
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
        try:
            return float(v) if v is not None else 0.0
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
    """
    yt-dlp writes thumbnails next to the video file with the same stem.
    Move them to output_dir/.thumbs/ and return the new path, or None.
    """
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
# Main download routine
# ---------------------------------------------------------------------------

def download(url: str, output_dir: Path, platform: str) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    # Snapshot existing files before download so we can find the new one
    existing_files = set(output_dir.iterdir())

    output_template = str(output_dir / "%(title).80s_%(id)s.%(ext)s")

    # yt-dlp progress JSON template (one JSON object per progress line)
    progress_template = (
        '{"status":"%(progress.status)s",'
        '"_percent_str":"%(progress._percent_str)s",'
        '"downloaded_bytes":%(progress.downloaded_bytes)s,'
        '"total_bytes":%(progress.total_bytes)s,'
        '"total_bytes_estimate":%(progress.total_bytes_estimate)s,'
        '"eta":%(progress.eta)s}'
    )

    ytdlp_args = [
        "--merge-output-format", "mp4",
        "--write-thumbnail",
        "--convert-thumbnails", "jpg",
        "--newline",
        "--progress-template", progress_template,
        "--output", output_template,
        url,
    ]

    ytdlp_bin = _find_ytdlp()
    if not ytdlp_bin:
        die("yt-dlp not found. Install it and try again.", "MISSING_DEPENDENCY")

    cmd = [ytdlp_bin] + ytdlp_args

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        die("yt-dlp not found. Install it and try again.", "MISSING_DEPENDENCY")

    assert proc.stdout is not None  # noqa: S101 – guaranteed by PIPE
    stderr_lines: list[str] = []

    # Stream stdout line by line
    for raw_line in proc.stdout:
        progress = _parse_progress_line(raw_line)
        if progress:
            emit(progress)

    # Collect stderr for error reporting
    if proc.stderr:
        stderr_lines = proc.stderr.readlines()

    proc.wait()

    if proc.returncode != 0:
        stderr_text = "".join(stderr_lines).strip()
        die(
            f"yt-dlp exited with code {proc.returncode}. {stderr_text}",
            "YTDLP_ERROR",
        )

    # Find the newly downloaded file (files that didn't exist before)
    new_files = set(output_dir.iterdir()) - existing_files
    downloaded_file: Optional[Path] = None

    # Prefer video files
    for candidate in sorted(new_files):
        if candidate.is_file() and candidate.suffix.lower() in (".mp4", ".mkv", ".webm", ".mov"):
            downloaded_file = candidate
            break

    if downloaded_file is None:
        # Maybe it was an image (e.g. Instagram photo)
        for candidate in sorted(new_files):
            if candidate.is_file() and candidate.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif"):
                downloaded_file = candidate
                break

    if downloaded_file is None:
        die("Download appeared to succeed but no output file was found.", "NO_OUTPUT_FILE")

    assert downloaded_file is not None  # for type checker

    # Determine media type
    media_type = "image" if downloaded_file.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif") else "video"

    # Move thumbnail
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


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="ClipGrab download engine — wraps yt-dlp with a JSON protocol.",
    )
    parser.add_argument("url", help="URL to download")
    parser.add_argument("--output-dir", required=True, help="Directory to save downloads")
    args = parser.parse_args()

    url: str = args.url
    output_dir = Path(args.output_dir)

    # 1. Validate URL
    validate_url(url)

    # 2. Detect platform
    platform = detect_platform(url)

    # 3. Check dependencies
    check_dependencies()

    # 4. Download
    download(url, output_dir, platform)


if __name__ == "__main__":
    main()
