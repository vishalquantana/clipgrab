# Quality Setting, Audio Extraction & Larger Previews — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a download quality/format setting (Best/1080p/720p/Audio-only-MP3), on-demand MP3 extraction from any downloaded video, and larger history previews to the macOS ClipGrab app.

**Architecture:** The shared Python engine (`download_manager.py`) gains a backward-compatible `--quality` flag that maps to yt-dlp format/extract args. The Swift app passes the new `quality` setting through `DownloadEngine` → engine. A new `.audio` media type renders audio downloads correctly. A per-row "copy MP3" button runs ffmpeg to extract+copy audio. History thumbnails grow 56×42 → 84×63.

**Tech Stack:** Python 3 + yt-dlp + ffmpeg (engine); Swift/SwiftUI/AppKit (macOS UI).

**Verification note:** This repo has no Swift unit-test target, so Swift tasks are verified with `swift build` and a manual run. The Python engine is verified via a CLI smoke check. Build the macOS app from the `macos/` directory.

---

## Task 1: Engine — add `--quality` flag

**Files:**
- Modify: `engine/download_manager.py`

- [ ] **Step 1: Add the argparse option**

In `main()` (around line 488-494), add the `--quality` argument and pass it through. Replace:

```python
    parser.add_argument("url", help="URL to download")
    parser.add_argument("--output-dir", required=True, help="Directory to save downloads")
    args = parser.parse_args()

    url: str = args.url
    output_dir = Path(args.output_dir)

    validate_url(url)
    platform = detect_platform(url)
    _ensure_path()
    download(url, output_dir, platform)
```

with:

```python
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
```

- [ ] **Step 2: Thread `quality` through `download()`**

Replace the `download()` signature and body (lines 465-481):

```python
def download(url: str, output_dir: Path, platform: str) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    existing_files = set(output_dir.iterdir())

    # For Twitter/X, try the syndication API first (yt-dlp hangs on guest token)
    if platform == "twitter":
        success = _download_twitter_direct(url, output_dir)
        if success:
            return

    # Try yt-dlp
    if _find_ytdlp():
        success = _download_via_ytdlp(url, output_dir, platform, existing_files)
        if success:
            return

    die("Download failed. yt-dlp could not process this URL.", "ALL_METHODS_FAILED")
```

with:

```python
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
```

- [ ] **Step 3: Build quality-specific yt-dlp args**

In `_download_via_ytdlp`, change the signature (line 345) from:

```python
def _download_via_ytdlp(url: str, output_dir: Path, platform: str, existing_files: set) -> bool:
```

to:

```python
def _download_via_ytdlp(url: str, output_dir: Path, platform: str, existing_files: set, quality: str = "best") -> bool:
```

Then replace the `ytdlp_args` block (lines 361-368):

```python
    ytdlp_args = [
        "--merge-output-format", "mp4",
        "--write-thumbnail",
        "--convert-thumbnails", "jpg",
        "--newline",
        "--progress-template", progress_template,
        "--output", output_template,
    ]
```

with:

```python
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
```

- [ ] **Step 4: Recognize audio files in result detection**

Replace the extension definitions and detection block (lines 422-446). The current block is:

```python
    video_exts = (".mp4", ".mkv", ".webm", ".mov")
    image_exts = (".jpg", ".jpeg", ".png", ".gif")

    # 1. Check newly created files
    for candidate in sorted(new_files):
        if candidate.is_file() and candidate.suffix.lower() in video_exts:
            downloaded_file = candidate
            break
    if downloaded_file is None:
        for candidate in sorted(new_files):
            if candidate.is_file() and candidate.suffix.lower() in image_exts:
                downloaded_file = candidate
                break

    # 2. Fall back: find existing file matching the video ID
    if downloaded_file is None and video_id:
        for candidate in sorted(output_dir.iterdir()):
            if candidate.is_file() and video_id in candidate.name and candidate.suffix.lower() in video_exts:
                downloaded_file = candidate
                break

    if downloaded_file is None:
        return False

    media_type = "image" if downloaded_file.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif") else "video"
```

Replace it with:

```python
    video_exts = (".mp4", ".mkv", ".webm", ".mov")
    image_exts = (".jpg", ".jpeg", ".png", ".gif")
    audio_exts = (".mp3", ".m4a", ".opus", ".aac", ".wav")

    # Search order depends on quality: audio downloads look for audio files first.
    if quality == "audio":
        ext_order = (audio_exts, video_exts, image_exts)
    else:
        ext_order = (video_exts, image_exts, audio_exts)

    # 1. Check newly created files
    for exts in ext_order:
        for candidate in sorted(new_files):
            if candidate.is_file() and candidate.suffix.lower() in exts:
                downloaded_file = candidate
                break
        if downloaded_file is not None:
            break

    # 2. Fall back: find existing file matching the video ID
    if downloaded_file is None and video_id:
        match_exts = audio_exts if quality == "audio" else video_exts
        for candidate in sorted(output_dir.iterdir()):
            if candidate.is_file() and video_id in candidate.name and candidate.suffix.lower() in match_exts:
                downloaded_file = candidate
                break

    if downloaded_file is None:
        return False

    suffix = downloaded_file.suffix.lower()
    if suffix in audio_exts:
        media_type = "audio"
    elif suffix in image_exts:
        media_type = "image"
    else:
        media_type = "video"
```

- [ ] **Step 5: Smoke-test the CLI**

Run: `python3 engine/download_manager.py --help`
Expected: help text lists `--quality` with choices `{best,1080,720,audio}`.

Run: `python3 engine/download_manager.py "http://x" --output-dir /tmp/cg --quality bogus`
Expected: argparse error (exit code 2) rejecting the invalid choice.

Run: `python3 engine/download_manager.py "notaurl" --output-dir /tmp/cg`
Expected: a JSON error line about the URL (confirms calling WITHOUT `--quality` still works — Windows back-compat).

- [ ] **Step 6: Commit**

```bash
git add engine/download_manager.py
git commit -m "feat(engine): add --quality flag (best/1080/720/audio) to download manager"
```

---

## Task 2: AppSettings — add `quality` field

**Files:**
- Modify: `macos/ClipGrab/Models/AppSettings.swift`

- [ ] **Step 1: Add the published property and coding key**

Add `@Published var quality: String` after the `mediaType` line (line 6), so the top of the class reads:

```swift
class AppSettings: ObservableObject, Codable {
    @Published var downloadFolder: String
    @Published var mediaType: String
    @Published var quality: String
    @Published var autoCopyToClipboard: Bool
```

Add `case quality` to `CodingKeys` after `case mediaType`:

```swift
    enum CodingKeys: String, CodingKey {
        case downloadFolder
        case mediaType
        case quality
        case autoCopyToClipboard
        case notificationsEnabled
        case launchAtLogin
        case enabledPlatforms
        case historyLimit
    }
```

- [ ] **Step 2: Add to the designated initializer**

Add a `quality` parameter (default `"best"`) and assignment. Update the `init` signature line `mediaType: String = "all",` region to include it, and add the assignment after `self.mediaType = mediaType`:

```swift
    init(
        downloadFolder: String? = nil,
        mediaType: String = "all",
        quality: String = "best",
        autoCopyToClipboard: Bool = true,
        notificationsEnabled: Bool = true,
        launchAtLogin: Bool = false,
        enabledPlatforms: [String: Bool] = [:],
        historyLimit: Int = 50
    ) {
        let fileManager = FileManager.default
        let defaultDownloadFolder = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipGrab")
            .path

        self.downloadFolder = downloadFolder ?? defaultDownloadFolder
        self.mediaType = mediaType
        self.quality = quality
        self.autoCopyToClipboard = autoCopyToClipboard
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.enabledPlatforms = enabledPlatforms
        self.historyLimit = historyLimit
    }
```

- [ ] **Step 3: Decode with a default (back-compat for old settings.json)**

In `init(from decoder:)`, after the `mediaType` decode line, add a defaulted decode:

```swift
        mediaType = try container.decode(String.self, forKey: .mediaType)
        quality = (try? container.decode(String.self, forKey: .quality)) ?? "best"
```

- [ ] **Step 4: Encode the field**

In `encode(to:)`, after the `mediaType` encode line, add:

```swift
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(quality, forKey: .quality)
```

- [ ] **Step 5: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add macos/ClipGrab/Models/AppSettings.swift
git commit -m "feat(settings): add persisted quality setting (defaults to best)"
```

---

## Task 3: Settings UI — Quality picker

**Files:**
- Modify: `macos/ClipGrab/Views/SettingsView.swift`

- [ ] **Step 1: Add the Quality GroupBox**

Insert a new `GroupBox` directly after the closing `}` of the existing `GroupBox("Media Type")` block (after line 39) and before `GroupBox("Monitored Platforms")`:

```swift
            GroupBox("Quality") {
                Picker("Download quality", selection: $settings.quality) {
                    Text("Best available").tag("best")
                    Text("1080p").tag("1080")
                    Text("720p").tag("720")
                    Text("Audio only (MP3)").tag("audio")
                }
                .pickerStyle(.radioGroup)
                .padding(4)
            }
```

- [ ] **Step 2: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add macos/ClipGrab/Views/SettingsView.swift
git commit -m "feat(settings): add quality picker to settings view"
```

---

## Task 4: Pass quality through DownloadEngine → engine

**Files:**
- Modify: `macos/ClipGrab/Services/DownloadEngine.swift`
- Modify: `macos/ClipGrab/Services/DownloadQueue.swift`

- [ ] **Step 1: Add `quality` parameter to `DownloadEngine.download`**

Change the method signature (line 39) from:

```swift
    func download(url: String, outputDir: String, onProgress: @escaping (ProgressUpdate) -> Void, onComplete: @escaping (CompletionResult) -> Void, onError: @escaping (DownloadError) -> Void) {
```

to:

```swift
    func download(url: String, outputDir: String, quality: String = "best", onProgress: @escaping (ProgressUpdate) -> Void, onComplete: @escaping (CompletionResult) -> Void, onError: @escaping (DownloadError) -> Void) {
```

And change the process arguments line (line 43) from:

```swift
            process.arguments = [scriptPath, url, "--output-dir", outputDir]
```

to:

```swift
            process.arguments = [scriptPath, url, "--output-dir", outputDir, "--quality", quality]
```

- [ ] **Step 2: Pass `settings.quality` from the queue**

In `DownloadQueue.processNext()`, change the engine call (line 36) from:

```swift
        engine.download(url: item.url, outputDir: settings.downloadFolder,
            onProgress: { [weak self] progress in
```

to:

```swift
        engine.download(url: item.url, outputDir: settings.downloadFolder, quality: settings.quality,
            onProgress: { [weak self] progress in
```

- [ ] **Step 3: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add macos/ClipGrab/Services/DownloadEngine.swift macos/ClipGrab/Services/DownloadQueue.swift
git commit -m "feat: pass quality setting through to the download engine"
```

---

## Task 5: Audio media type

**Files:**
- Modify: `macos/ClipGrab/Models/DownloadItem.swift`
- Modify: `macos/ClipGrab/Services/DownloadQueue.swift`

- [ ] **Step 1: Add `.audio` to MediaType**

Change the enum (lines 10-13) from:

```swift
enum MediaType: String, Codable {
    case video
    case image
}
```

to:

```swift
enum MediaType: String, Codable {
    case video
    case image
    case audio
}
```

- [ ] **Step 2: Map the audio media type on completion**

In `DownloadQueue.processNext()`'s `onComplete` closure, change the mediaType mapping (line 50) from:

```swift
                self.currentDownload?.mediaType = result.mediaType == "video" ? .video : .image
```

to:

```swift
                switch result.mediaType {
                case "audio": self.currentDownload?.mediaType = .audio
                case "image": self.currentDownload?.mediaType = .image
                default: self.currentDownload?.mediaType = .video
                }
```

- [ ] **Step 3: Build**

Run: `cd macos && swift build`
Expected: build succeeds. (Note: the `switch` over `MediaType` in `DownloadItemRow` is handled in Task 7; until then the row treats `.audio` like a non-image via its `if` checks, which still compiles.)

- [ ] **Step 4: Commit**

```bash
git add macos/ClipGrab/Models/DownloadItem.swift macos/ClipGrab/Services/DownloadQueue.swift
git commit -m "feat: add audio media type and map it from engine results"
```

---

## Task 6: ffmpeg locator + audio extraction/clipboard

**Files:**
- Modify: `macos/ClipGrab/Services/DownloadEngine.swift`
- Modify: `macos/ClipGrab/Services/DownloadQueue.swift`

- [ ] **Step 1: Add a static `findFFmpeg()` to DownloadEngine**

Add this method to the `DownloadEngine` class, right after `findPython()` (after line 92, before the closing `}` of the class):

```swift
    static func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Fallback: search PATH via `which`.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !out.isEmpty, FileManager.default.fileExists(atPath: out) {
                return out
            }
        } catch {
            return nil
        }
        return nil
    }
```

- [ ] **Step 2: Add `copyAudioToClipboard` to DownloadQueue**

Add this method to `DownloadQueue`, right after the existing `copyToClipboard(_:)` method (after line 87):

```swift
    /// Extracts audio (MP3) from a downloaded video via ffmpeg and copies it to the clipboard.
    /// The MP3 is cached next to the source so repeat clicks are instant.
    func copyAudioToClipboard(_ item: DownloadItem, completion: @escaping (Bool) -> Void) {
        guard let filePath = item.filePath,
              FileManager.default.fileExists(atPath: filePath) else {
            completion(false)
            return
        }

        let videoURL = URL(fileURLWithPath: filePath)
        let mp3URL = videoURL.deletingPathExtension().appendingPathExtension("mp3")

        func copyToPasteboard() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([mp3URL as NSURL])
        }

        // Reuse a previously extracted, non-empty MP3.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: mp3URL.path),
           (attrs[.size] as? Int64 ?? 0) > 0 {
            copyToPasteboard()
            completion(true)
            return
        }

        guard let ffmpeg = DownloadEngine.findFFmpeg() else {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y", "-i", videoURL.path,
                "-vn", "-acodec", "libmp3lame", "-q:a", "2",
                mp3URL.path,
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            var success = false
            do {
                try process.run()
                process.waitUntilExit()
                let size = (try? FileManager.default.attributesOfItem(atPath: mp3URL.path)[.size] as? Int64) ?? 0
                success = process.terminationStatus == 0 && (size ?? 0) > 0
            } catch {
                success = false
            }

            DispatchQueue.main.async {
                if success { copyToPasteboard() }
                completion(success)
            }
        }
    }
```

- [ ] **Step 3: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add macos/ClipGrab/Services/DownloadEngine.swift macos/ClipGrab/Services/DownloadQueue.swift
git commit -m "feat: extract MP3 from a downloaded video and copy it to the clipboard"
```

---

## Task 7: DownloadItemRow — larger previews, audio icon, copy-MP3 button

**Files:**
- Modify: `macos/ClipGrab/Views/DownloadItemRow.swift`

- [ ] **Step 1: Add the new closure and state to `DownloadItemRow`**

Change the struct's stored properties (lines 75-82) from:

```swift
struct DownloadItemRow: View {
    let item: DownloadItem
    let onCopy: () -> Void
    @State private var showCopied = false
    @State private var showLinkCopied = false
    @State private var isHovering = false
    @State private var scrubFraction: CGFloat = 0
```

to:

```swift
struct DownloadItemRow: View {
    let item: DownloadItem
    let onCopy: () -> Void
    var onCopyAudio: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    @State private var showCopied = false
    @State private var showLinkCopied = false
    @State private var showMp3Copied = false
    @State private var isExtractingAudio = false
    @State private var isHovering = false
    @State private var scrubFraction: CGFloat = 0
```

- [ ] **Step 2: Enlarge thumbnails to 84×63 and handle the audio case**

Replace the entire thumbnail `ZStack { ... }` and its frame/overlay (lines 86-138) with:

```swift
            // Thumbnail / video preview
            ZStack {
                if item.mediaType == .audio {
                    audioThumbnail
                } else if let thumbPath = item.thumbnailPath, FileManager.default.fileExists(atPath: thumbPath) {
                    // Show real thumbnail, play video on hover
                    if isHovering, item.mediaType == .video, let filePath = item.filePath, FileManager.default.fileExists(atPath: filePath) {
                        VideoThumbnailView(filePath: filePath, isHovering: isHovering, scrubFraction: scrubFraction)
                            .frame(width: 84, height: 63)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if let nsImage = NSImage(contentsOfFile: thumbPath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 84, height: 63)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                // Play icon overlay for videos
                                Group {
                                    if item.mediaType == .video {
                                        Circle()
                                            .fill(.black.opacity(0.45))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white)
                                                    .offset(x: 1)
                                            )
                                    }
                                }
                            )
                    } else {
                        fallbackThumbnail
                    }
                } else {
                    fallbackThumbnail
                }
            }
            .frame(width: 84, height: 63)
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                scrubFraction = max(0, min(1, location.x / geo.size.width))
                            case .ended:
                                break
                            @unknown default:
                                break
                            }
                        }
                }
            )
```

- [ ] **Step 3: Add the MP3-copied feedback line**

In the `VStack(alignment: .leading, spacing: 2)`, extend the copied-feedback block (lines 157-167) from:

```swift
                if showCopied {
                    Text("Copied to clipboard!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green.opacity(0.8))
                        .transition(.opacity)
                } else if showLinkCopied {
                    Text("Link copied!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue.opacity(0.8))
                        .transition(.opacity)
                }
```

to:

```swift
                if showCopied {
                    Text("Copied to clipboard!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green.opacity(0.8))
                        .transition(.opacity)
                } else if showLinkCopied {
                    Text("Link copied!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue.opacity(0.8))
                        .transition(.opacity)
                } else if showMp3Copied {
                    Text("MP3 copied!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .transition(.opacity)
                } else if isExtractingAudio {
                    Text("Extracting MP3...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .transition(.opacity)
                }
```

- [ ] **Step 4: Add the copy-MP3 button to the action buttons**

In the `if item.status == .complete {` block, add the MP3 button before the existing "Copy original URL" link button (line 171). The block becomes:

```swift
            if item.status == .complete {
                if item.mediaType == .video {
                    Button(action: copyAudio) {
                        if isExtractingAudio {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 28)
                    .disabled(isExtractingAudio)
                    .help("Extract & copy MP3")
                }

                Button(action: copyLink) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .help("Copy original URL")

                Button(action: copyMedia) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .help("Copy media to clipboard")
            } else if item.status == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
```

- [ ] **Step 5: Add the animation trigger for the new states**

Change the two `.animation` modifiers (lines 200-201) from:

```swift
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .animation(.easeInOut(duration: 0.2), value: showLinkCopied)
```

to:

```swift
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .animation(.easeInOut(duration: 0.2), value: showLinkCopied)
        .animation(.easeInOut(duration: 0.2), value: showMp3Copied)
        .animation(.easeInOut(duration: 0.2), value: isExtractingAudio)
```

- [ ] **Step 6: Add the `copyAudio` action and `audioThumbnail`, and enlarge `fallbackThumbnail`**

Add the `copyAudio()` method right after the existing `copyLink()` method (after line 245):

```swift
    private func copyAudio() {
        guard !isExtractingAudio else { return }
        isExtractingAudio = true
        showCopied = false
        showLinkCopied = false
        showMp3Copied = false
        onCopyAudio { success in
            isExtractingAudio = false
            if success {
                showMp3Copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    showMp3Copied = false
                }
            }
        }
    }
```

Replace the `fallbackThumbnail` computed view (lines 204-226) to use the larger 84×63 size and a bigger play badge:

```swift
    @ViewBuilder
    private var fallbackThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(platformGradient)
                .frame(width: 84, height: 63)
            if item.mediaType == .video {
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.black)
                            .offset(x: 1)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var audioThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(platformGradient)
                .frame(width: 84, height: 63)
            if let thumbPath = item.thumbnailPath,
               FileManager.default.fileExists(atPath: thumbPath),
               let nsImage = NSImage(contentsOfFile: thumbPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 84, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25)))
            }
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.95))
        }
    }
```

- [ ] **Step 7: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add macos/ClipGrab/Views/DownloadItemRow.swift
git commit -m "feat(ui): larger previews, audio rows, and per-item copy-MP3 button"
```

---

## Task 8: Wire `onCopyAudio` in MenuBarView

**Files:**
- Modify: `macos/ClipGrab/Views/MenuBarView.swift`

- [ ] **Step 1: Pass the audio closure into the row**

Change the `ForEach` row construction (lines 84-88) from:

```swift
                    ForEach(downloadQueue.history.prefix(5)) { item in
                        DownloadItemRow(item: item) {
                            downloadQueue.copyToClipboard(item)
                        }
                    }
```

to:

```swift
                    ForEach(downloadQueue.history.prefix(5)) { item in
                        DownloadItemRow(
                            item: item,
                            onCopy: { downloadQueue.copyToClipboard(item) },
                            onCopyAudio: { completion in downloadQueue.copyAudioToClipboard(item, completion: completion) }
                        )
                    }
```

- [ ] **Step 2: Build**

Run: `cd macos && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add macos/ClipGrab/Views/MenuBarView.swift
git commit -m "feat: wire per-item MP3 extraction into the menu bar list"
```

---

## Task 9: Build the app bundle and manually verify

**Files:** none (verification only)

- [ ] **Step 1: Build the release app bundle**

Run: `cd macos && swift build -c release && bash build_app.sh`
Expected: `ClipGrab.app` is produced without errors.

- [ ] **Step 2: Launch and verify**

Run: `open macos/ClipGrab.app`

Verify the following manually:
- Open Settings → a "Quality" group shows Best / 1080p / 720p / Audio only (MP3); changing it and reopening Settings shows the choice persisted (check `~/Library/Application Support/ClipGrab/settings.json` contains `"quality"`).
- With quality "Best", copy a public video link → it downloads and the history thumbnail is visibly larger (84×63).
- Hover a video row → the existing scrub-to-preview still works.
- Click the `music.note` button on a video row → shows "Extracting MP3..." then "MP3 copied!"; paste into Finder yields an `.mp3`. Clicking again is instant (cached).
- Set quality "Audio only (MP3)" and download a video link → the row shows a music-note thumbnail and the file on disk is an `.mp3`.

- [ ] **Step 3: Update CHANGELOG/README if present**

If `README.md`'s Features list or a CHANGELOG is maintained, add bullets for: quality selection, audio-only (MP3) downloads, per-item MP3 extraction, larger previews. (Skip if no such section exists.)

- [ ] **Step 4: Commit any doc updates**

```bash
git add README.md
git commit -m "docs: document quality, audio extraction, and larger previews"
```

---

## Self-review checklist (completed by plan author)

- **Spec coverage:** Quality setting (Tasks 2-4), audio-only download (Tasks 1,5,7), per-item MP3 copy (Tasks 6-8), larger previews (Task 7), back-compat default (Tasks 1-2). Download-folder chooser already exists (no task, per spec). Media-type wiring intentionally out of scope.
- **Type consistency:** `copyAudioToClipboard(_:completion:)` signature matches its call in Task 8; `onCopyAudio: (@escaping (Bool) -> Void) -> Void` matches the closure passed in Task 8 and invoked in Task 7's `copyAudio`. `findFFmpeg()` defined in Task 6, used in Task 6. `MediaType.audio` defined in Task 5, used in Tasks 5 and 7. `--quality` values (`best/1080/720/audio`) consistent across engine (Task 1), settings tags (Task 3), and engine plumbing (Task 4).
- **Placeholders:** none — all steps contain concrete code/commands.
