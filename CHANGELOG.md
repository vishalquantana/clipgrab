# Changelog

## v1.0.2 — 2026-05-26

### Bug Fixes
- **Duplicate detection** — already-downloaded files are now detected, preventing re-downloads
- **Retry failed downloads** — failed downloads can now be retried from the history list
- **yt-dlp + ffmpeg integration** — yt-dlp now correctly finds ffmpeg; tolerates non-zero exit codes when file was actually downloaded
- **Windows: yt-dlp discovery** — fixed finding yt-dlp in Python Scripts directory with `shutil.which` fallback
- **Windows: build workflow** — `.exe` artifact now uploaded on manual workflow trigger too

## v1.0.1 — 2026-05-21

### New Features
- **Video scrub preview** — hover over a thumbnail and move your mouse left-to-right to scrub through the video
- **Twitter/X direct download** — uses Twitter's syndication API as a fast fallback when yt-dlp struggles with guest tokens
- **Paste URL input** — click the + button to manually paste a URL for download

### Bug Fixes
- **Windows: file now copied to clipboard** after download — paste directly into Slack, email, etc.
- **Windows: notifications show ClipGrab icon** and "ClipGrab by Quantana" instead of Python branding
- **Progress bar** no longer stuck at 0% during downloads
- **Menu bar progress ring** shows download progress on the tray icon
- **URL deduplication** handles tracking query params (`?s=20`, `?utm_source=...`)
- **Correct titles** — each download now shows its own title instead of duplicating previous ones

### Improvements
- Download engine tries Twitter syndication API first for Twitter/X URLs (faster)
- Added About Quantana section to README

## v1.0.0 — 2026-05-20

### Initial Release
- macOS menu bar app with clipboard monitoring
- Windows system tray app (beta)
- Supports 11 platforms: Instagram, YouTube, TikTok, Twitter/X, Reddit, Facebook, Threads, Vimeo, Pinterest, Twitch, LinkedIn
- Automatic download + clipboard copy on URL detection
- Video thumbnail previews in download history
- Setup assistant for first-launch dependency installation
- Shared Python download engine across platforms
