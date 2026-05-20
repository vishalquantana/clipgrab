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

        // Take only the first line/word in case extra text was copied
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).first ?? ""

        let normalized = Self.normalizeURL(trimmed)
        guard !processedURLs.contains(normalized) else { return }
        guard let platform = patterns.matchingPlatform(for: trimmed) else { return }
        guard settings.enabledPlatforms[platform.id] ?? true else { return }

        processedURLs.insert(normalized)
        detectedURL = (url: trimmed, platform: platform)
    }

    /// Strip tracking query params so ?s=20 and bare URL are treated as the same
    private static func normalizeURL(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        // Remove common tracking params
        let trackingParams: Set<String> = ["s", "utm_source", "utm_medium", "utm_campaign", "utm_content", "igsh", "rcm", "ref", "ref_src", "ref_url"]
        if let items = components.queryItems {
            let filtered = items.filter { !trackingParams.contains($0.name) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.string ?? url
    }

    func markProcessed(_ url: String) {
        processedURLs.insert(url)
    }
}
