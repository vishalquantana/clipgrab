import AppKit
import Combine

class ClipboardMonitor: ObservableObject {
    @Published var detectedURL: (url: String, platform: PlatformPattern)?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var processedURLs: Set<String> = []
    private let patterns: PlatformPatterns
    private let settings: AppSettings

    init(patterns: PlatformPatterns, settings: AppSettings) {
        self.patterns = patterns
        self.settings = settings
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let content = pasteboard.string(forType: .string) else { return }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !processedURLs.contains(trimmed) else { return }
        guard let platform = patterns.matchingPlatform(for: trimmed) else { return }
        guard settings.enabledPlatforms[platform.id] ?? true else { return }

        processedURLs.insert(trimmed)
        detectedURL = (url: trimmed, platform: platform)
    }

    func markProcessed(_ url: String) {
        processedURLs.insert(url)
    }
}
