import Foundation
import Combine

class AppSettings: ObservableObject, Codable {
    @Published var downloadFolder: String
    @Published var mediaType: String
    @Published var quality: String
    @Published var autoCopyToClipboard: Bool
    @Published var notificationsEnabled: Bool
    @Published var launchAtLogin: Bool
    @Published var enabledPlatforms: [String: Bool]
    @Published var historyLimit: Int

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

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadFolder = try container.decode(String.self, forKey: .downloadFolder)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        quality = (try? container.decode(String.self, forKey: .quality)) ?? "best"
        autoCopyToClipboard = try container.decode(Bool.self, forKey: .autoCopyToClipboard)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        enabledPlatforms = try container.decode([String: Bool].self, forKey: .enabledPlatforms)
        historyLimit = try container.decode(Int.self, forKey: .historyLimit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(downloadFolder, forKey: .downloadFolder)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(quality, forKey: .quality)
        try container.encode(autoCopyToClipboard, forKey: .autoCopyToClipboard)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(enabledPlatforms, forKey: .enabledPlatforms)
        try container.encode(historyLimit, forKey: .historyLimit)
    }

    static func load() -> AppSettings {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let clipgrabDir = appSupportDir.appendingPathComponent("ClipGrab")
        let settingsFile = clipgrabDir.appendingPathComponent("settings.json")

        if fileManager.fileExists(atPath: settingsFile.path) {
            do {
                let data = try Data(contentsOf: settingsFile)
                let decoder = JSONDecoder()
                return try decoder.decode(AppSettings.self, from: data)
            } catch {
                return AppSettings()
            }
        } else {
            return AppSettings()
        }
    }

    func save() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let clipgrabDir = appSupportDir.appendingPathComponent("ClipGrab")
        let settingsFile = clipgrabDir.appendingPathComponent("settings.json")

        if !fileManager.fileExists(atPath: clipgrabDir.path) {
            try? fileManager.createDirectory(at: clipgrabDir, withIntermediateDirectories: true)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: settingsFile)
        } catch {
            // Handle error silently or log as needed
        }
    }
}
