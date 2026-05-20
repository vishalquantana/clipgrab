# ClipGrab

ClipGrab is a macOS menu bar utility that monitors your clipboard for social media URLs and automatically downloads the video or photo at the highest available quality, converts it to MP4, and places it back on your clipboard — ready to paste anywhere.

## Features

- Monitors clipboard for Instagram, Twitter/X, and LinkedIn URLs
- Downloads media at the highest available quality
- Automatically converts downloaded media to MP4
- Places the downloaded file directly on your clipboard
- Runs quietly in the macOS menu bar — no dock icon, no clutter

## Requirements

- macOS 13 (Ventura) or later
- Python 3.9 or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/)

## Architecture

ClipGrab is built with two layers:

- **Swift/SwiftUI shell** (`macos/`) — The macOS menu bar app. Manages the status item, clipboard monitoring, and user interface.
- **Python engine** (`engine/`) — Handles URL detection, media downloading via `yt-dlp`, and MP4 conversion via `ffmpeg`.

## Getting Started

### Install dependencies

```bash
# Python engine dependencies
pip install -r engine/requirements.txt

# ffmpeg (via Homebrew)
brew install ffmpeg
```

### Build the macOS app

Open `macos/` in Xcode and build the `ClipGrab` target, or use Swift Package Manager:

```bash
cd macos
swift build
```

### Run

Launch the built `ClipGrab.app`. An arrow icon will appear in your menu bar. Copy any Instagram, Twitter/X, or LinkedIn URL — ClipGrab will handle the rest.

## Supported Platforms

| Platform  | Support |
|-----------|---------|
| Instagram | Yes     |
| Twitter/X | Yes     |
| LinkedIn  | Yes     |

## License

MIT License — see [LICENSE](LICENSE) for details.
