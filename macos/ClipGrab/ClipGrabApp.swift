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
            button.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "ClipGrab")
            button.action = #selector(togglePopover)
            button.target = self
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
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
                        mediaType: latest.mediaType?.rawValue ?? "video"
                    )
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
