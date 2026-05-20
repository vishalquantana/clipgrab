import Foundation

enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case complete
    case failed
}

enum MediaType: String, Codable {
    case video
    case image
}

struct DownloadItem: Identifiable, Codable {
    let id: UUID
    let url: String
    let platform: String
    var title: String
    var status: DownloadStatus
    var mediaType: MediaType
    var filePath: String?
    var thumbnailPath: String?
    var fileSize: Int64?
    var progress: Double
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var etaSeconds: Int?
    var errorMessage: String?
    var createdAt: Date

    init(url: String, platform: String) {
        self.id = UUID()
        self.url = url
        self.platform = platform
        self.title = ""
        self.status = .queued
        self.mediaType = .video
        self.filePath = nil
        self.thumbnailPath = nil
        self.fileSize = nil
        self.progress = 0.0
        self.downloadedBytes = nil
        self.totalBytes = nil
        self.etaSeconds = nil
        self.errorMessage = nil
        self.createdAt = Date()
    }
}
