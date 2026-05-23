import SwiftUI
import Combine

@main
struct ClipGrabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let settings = AppSettings.load()
    private lazy var patterns = PlatformPatterns.load()
    private lazy var clipboardMonitor = ClipboardMonitor(patterns: patterns, settings: settings)
    private lazy var downloadQueue = DownloadQueue(settings: settings)
    private let historyStore = HistoryStore()
    private var cancellables = Set<AnyCancellable>()
    private var setupWindow: NSWindow?
    private var eventMonitor: Any?
    private var tooltipTimer: Timer?
    private var progressCancellable: AnyCancellable?
    private var baseIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.shared.requestPermission()

        try? FileManager.default.createDirectory(
            atPath: settings.downloadFolder,
            withIntermediateDirectories: true
        )

        if !commandExists("yt-dlp") || !commandExists("ffmpeg") {
            showSetupAssistant()
            return
        }

        startApp()
    }

    private func startApp() {
        cleanupPartialDownloads()
        setupMenuBar()
        loadHistory()
        startMonitoring()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let iconPath = Bundle.main.path(forResource: "menubar_icon_18x18", ofType: "png") {
                let img = NSImage(contentsOfFile: iconPath)
                img?.isTemplate = true
                img?.size = NSSize(width: 18, height: 18)
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "ClipGrab")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Store base icon for progress overlay
        baseIcon = statusItem?.button?.image

        // Observe download progress to update menu bar icon
        progressCancellable = downloadQueue.$currentDownload
            .receive(on: RunLoop.main)
            .sink { [weak self] current in
                self?.updateMenuBarIcon(download: current)
            }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(downloadQueue: downloadQueue, settings: settings)
        )
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func loadHistory() {
        let items = historyStore.loadRecent(limit: settings.historyLimit == 0 ? 100 : settings.historyLimit)
        downloadQueue.history = items
    }

    private func startMonitoring() {
        clipboardMonitor.start()

        clipboardMonitor.$detectedURL
            .compactMap { $0 }
            .sink { [weak self] detected in
                guard let self else { return }
                guard !self.historyStore.hasURL(detected.url) else { return }

                if self.settings.notificationsEnabled {
                    NotificationService.shared.notifyDownloadStarted(platform: detected.platform.name)
                }

                self.downloadQueue.enqueue(url: detected.url, platform: detected.platform.id)
            }
            .store(in: &cancellables)

        downloadQueue.$history
            .sink { [weak self] history in
                guard let self, let latest = history.first else { return }
                self.historyStore.save(latest)

                if latest.status == .complete && self.settings.notificationsEnabled {
                    NotificationService.shared.notifyDownloadComplete(
                        title: latest.title,
                        mediaType: latest.mediaType.rawValue
                    )
                    self.showMenuBarTooltip("Download done!")
                } else if latest.status == .failed && self.settings.notificationsEnabled {
                    NotificationService.shared.notifyError(
                        message: latest.errorMessage ?? "Download failed"
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func showSetupAssistant() {
        let view = SetupAssistantView {
            self.setupWindow?.close()
            self.startApp()
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "ClipGrab Setup"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.setupWindow = window
    }

    private func updateMenuBarIcon(download: DownloadItem?) {
        guard let button = statusItem?.button else { return }

        if let dl = download, dl.status == .downloading {
            let progress = dl.progress / 100.0
            let size: CGFloat = 18
            let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                // Draw base icon
                if let base = self.baseIcon {
                    base.draw(in: rect)
                }

                // Draw circular progress ring
                let center = CGPoint(x: size / 2, y: size / 2)
                let radius: CGFloat = size / 2 - 1
                let lineWidth: CGFloat = 2

                // Background ring
                let bgPath = NSBezierPath()
                bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                bgPath.lineWidth = lineWidth
                NSColor.white.withAlphaComponent(0.2).setStroke()
                bgPath.stroke()

                // Progress ring (clockwise from top)
                if progress > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle: CGFloat = 90 - (360 * CGFloat(progress))
                    let progressPath = NSBezierPath()
                    progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    progressPath.lineWidth = lineWidth
                    progressPath.lineCapStyle = .round
                    NSColor.systemBlue.setStroke()
                    progressPath.stroke()
                }

                return true
            }
            img.isTemplate = false
            button.image = img
        } else {
            // Restore base icon
            if let base = baseIcon {
                button.image = base
            }
        }
    }

    private func showMenuBarTooltip(_ message: String) {
        if let button = statusItem?.button {
            button.title = "  \(message)"
            tooltipTimer?.invalidate()
            tooltipTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.statusItem?.button?.title = ""
            }
        }
    }

    private func cleanupPartialDownloads() {
        let downloadDir = settings.downloadFolder
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: downloadDir) else { return }
        for file in files {
            let path = (downloadDir as NSString).appendingPathComponent(file)
            if file.hasSuffix(".part") || file.hasSuffix(".ytdl") {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    private func commandExists(_ name: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
