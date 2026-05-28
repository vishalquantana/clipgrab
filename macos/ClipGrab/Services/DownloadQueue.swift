import Foundation
import Combine
import AppKit

class DownloadQueue: ObservableObject {
    @Published var currentDownload: DownloadItem?
    @Published var history: [DownloadItem] = []
    @Published var queueCount: Int = 0

    private let engine = DownloadEngine()
    private var queue: [DownloadItem] = []
    private var isProcessing = false
    private var processedURLs: Set<String> = []
    private let settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    func enqueue(url: String, platform: String) {
        guard !processedURLs.contains(url) else { return }
        processedURLs.insert(url)
        var item = DownloadItem(url: url, platform: platform)
        item.status = .queued
        queue.append(item)
        queueCount = queue.count
        processNext()
    }

    private func processNext() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        var item = queue.removeFirst()
        queueCount = queue.count
        item.status = .downloading
        currentDownload = item

        engine.download(url: item.url, outputDir: settings.downloadFolder, quality: settings.quality,
            onProgress: { [weak self] progress in
                self?.currentDownload?.progress = progress.percent
                self?.currentDownload?.downloadedBytes = progress.downloadedBytes
                self?.currentDownload?.totalBytes = progress.totalBytes
                self?.currentDownload?.etaSeconds = progress.etaSeconds
            },
            onComplete: { [weak self] result in
                guard let self else { return }
                self.currentDownload?.status = .complete
                self.currentDownload?.title = result.title
                self.currentDownload?.filePath = result.filePath
                self.currentDownload?.thumbnailPath = result.thumbnailPath
                self.currentDownload?.fileSize = result.fileSize
                self.currentDownload?.mediaType = result.mediaType == "video" ? .video : .image
                self.currentDownload?.progress = 100
                if let completed = self.currentDownload {
                    self.history.insert(completed, at: 0)
                    self.trimHistory()
                    if self.settings.autoCopyToClipboard {
                        self.copyToClipboard(completed)
                    }
                }
                self.currentDownload = nil
                self.isProcessing = false
                self.processNext()
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.currentDownload?.status = .failed
                self.currentDownload?.errorMessage = error.message
                if let failed = self.currentDownload { self.history.insert(failed, at: 0) }
                self.currentDownload = nil
                self.isProcessing = false
                self.processNext()
            })
    }

    func retry(_ item: DownloadItem) {
        processedURLs.remove(item.url)
        history.removeAll { $0.id == item.id }
        enqueue(url: item.url, platform: item.platform)
    }

    func copyToClipboard(_ item: DownloadItem) {
        guard let filePath = item.filePath else { return }
        let fileURL = URL(fileURLWithPath: filePath)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }

    private func trimHistory() {
        let limit = settings.historyLimit
        if limit > 0 && history.count > limit { history = Array(history.prefix(limit)) }
    }
}
