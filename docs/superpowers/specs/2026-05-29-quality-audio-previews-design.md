# ClipGrab — Quality Setting, Audio Extraction & Larger Previews

**Date:** 2026-05-29
**Scope:** macOS app + shared Python engine. Windows tray UI is out of scope (engine changes stay backward-compatible).

## Goals

1. Let users choose download quality/format.
2. Let users download audio-only (MP3) and extract MP3 from any already-downloaded video.
3. Make the history video previews larger.

## Non-goals

- Wiring up the existing (currently dead) "Media Type" all/videos-only setting. Noted as a separate known issue.
- Windows tray UI changes.
- Trimming, playlists, subtitles, or other previously-discussed ideas.

---

## 1. Quality / format setting

### AppSettings (`macos/ClipGrab/Models/AppSettings.swift`)
- Add `@Published var quality: String` with default `"best"`.
- Add to `CodingKeys`, `init`, `encode`. In `init(from:)`, decode with a default so existing `settings.json` files (no `quality` key) keep working: `quality = (try? container.decode(String.self, forKey: .quality)) ?? "best"`.

Valid values: `"best"`, `"1080"`, `"720"`, `"audio"`.

### Settings UI (`macos/ClipGrab/Views/SettingsView.swift`)
- New `GroupBox("Quality")` with a `.radioGroup` Picker bound to `$settings.quality`:
  - "Best available" → `best`
  - "1080p" → `1080`
  - "720p" → `720`
  - "Audio only (MP3)" → `audio`
- Place it directly under the existing "Media Type" box.

### Engine plumbing
- `DownloadEngine.download(...)` gains a `quality: String` parameter; appends `"--quality", quality` to the process arguments.
- `DownloadQueue.processNext()` passes `settings.quality`.

### Python engine (`engine/download_manager.py`)
- Add argparse option: `--quality` with `choices=["best","1080","720","audio"]`, `default="best"`. Default keeps the Windows tray call (no `--quality`) working.
- Thread `quality` into `download()` → `_download_via_ytdlp()`.
- Build yt-dlp args by quality:
  - `best`: current behavior — `--merge-output-format mp4`, default format selection.
  - `1080`: add `-f "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"`, keep `--merge-output-format mp4`.
  - `720`: same with `height<=720`.
  - `audio`: use `-x --audio-format mp3 --audio-quality 0`; do **not** pass `--merge-output-format mp4`. Still `--write-thumbnail --convert-thumbnails jpg` for a cover image.
- Result detection: include `.mp3`/`.m4a` in the recognized extensions. When quality is `audio` (or the file is an audio ext), emit `"media_type": "audio"`.
- Twitter syndication path ignores quality (always best mp4); acceptable — it's a narrow fallback.

---

## 2. Audio media type

### `macos/ClipGrab/Models/DownloadItem.swift`
- Add `case audio` to `MediaType`.

### `macos/ClipGrab/Services/DownloadEngine.swift`
- Map completion `media_type`: `"video"` → `.video`, `"image"` → `.image`, `"audio"` → `.audio` (in `DownloadQueue.onComplete`, where the mapping currently lives).

### `macos/ClipGrab/Views/DownloadItemRow.swift`
- For `.audio` items: show a `music.note` badge in the thumbnail (reuse fallback styling), no hover video scrubbing, and do **not** show the per-item "copy MP3" button (it's already audio).

---

## 3. Per-item "copy MP3" icon

### ffmpeg locator
- Add a static `findFFmpeg()` to `DownloadEngine` (mirror `findPython()`): check `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`, then `which`-style fallback. Returns path or nil.

### Extraction + clipboard (`macos/ClipGrab/Services/DownloadQueue.swift`)
- New method `copyAudioToClipboard(_ item: DownloadItem, completion: @escaping (Bool) -> Void)`:
  - Guard `item.filePath` exists and is a video.
  - Target mp3 path = same dir + same stem + `.mp3`.
  - If it already exists and is non-empty, skip extraction (cache).
  - Else run ffmpeg off the main thread: `ffmpeg -y -i <video> -vn -acodec libmp3lame -q:a 2 <out.mp3>`.
  - On success, write the mp3 file URL to `NSPasteboard` (same pattern as `copyToClipboard`). Call `completion(true)` on the main thread; `completion(false)` on any failure (no ffmpeg, non-zero exit, missing output).

### Row UI (`macos/ClipGrab/Views/DownloadItemRow.swift`)
- Add `let onCopyAudio: (@escaping (Bool) -> Void) -> Void` to the row (alongside `onCopy`).
- Add a `music.note` button shown only when `status == .complete && mediaType == .video`, placed before the link button.
- Local `@State`: `isExtracting`, `showMp3Copied`. Tap → `isExtracting = true`, call `onCopyAudio { ok in isExtracting = false; showMp3Copied = ok }`. While extracting show a small `ProgressView` in place of the icon. Show "MP3 copied!" feedback line (green) like the existing copied states; auto-hide after ~10s.

### Wiring (`macos/ClipGrab/Views/MenuBarView.swift`)
- Pass `onCopyAudio: { completion in downloadQueue.copyAudioToClipboard(item, completion: completion) }` into `DownloadItemRow`.

---

## 4. Larger previews

### `macos/ClipGrab/Views/DownloadItemRow.swift`
- Change every `width: 56, height: 42` to `width: 84, height: 63` (VideoThumbnailView frame, real-image frame, outer ZStack frame, fallbackThumbnail rectangle).
- Scale the play badge from 20×20 circle / size-8 glyph to ~24×24 / size-10 so it stays proportional.

---

## Testing / verification

- Build the macOS app (`swift build -c release` + `build_app.sh`) and confirm it compiles.
- Run the app; verify:
  - Settings shows the Quality picker; selecting each value persists to `settings.json`.
  - A normal copy-link download at "Best" still works and previews are visibly larger.
  - "Audio only (MP3)" download yields an `.mp3` with a music-note row.
  - The per-item "copy MP3" button on a video row extracts and copies an mp3 (paste into Finder/Slack), showing progress then "MP3 copied!".
- Engine unit sanity: `python download_manager.py <url> --output-dir <tmp> --quality 720` and `--quality audio` produce the expected files; calling **without** `--quality` still works (Windows back-compat).
- Backward compat: load an old `settings.json` lacking `quality` → defaults to best, no crash.
