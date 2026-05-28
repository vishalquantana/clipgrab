import Foundation
import Combine

struct ProgressUpdate {
    var percent: Double
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var etaSeconds: Int?
}

struct CompletionResult {
    var filePath: String
    var title: String
    var platform: String
    var mediaType: String
    var fileSize: Int64
    var thumbnailPath: String?
}

struct DownloadError: Error {
    var message: String
    var code: String
}

class DownloadEngine {
    private let pythonPath: String
    private let scriptPath: String

    init() {
        self.pythonPath = Self.findPython()
        if let bundledScript = Bundle.main.url(forResource: "download_manager", withExtension: "py") {
            self.scriptPath = bundledScript.path
        } else {
            let appDir = Bundle.main.bundlePath
            self.scriptPath = (appDir as NSString).deletingLastPathComponent + "/../engine/download_manager.py"
        }
    }

    func download(url: String, outputDir: String, quality: String = "best", onProgress: @escaping (ProgressUpdate) -> Void, onComplete: @escaping (CompletionResult) -> Void, onError: @escaping (DownloadError) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [scriptPath, url, "--output-dir", outputDir, "--quality", quality]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.run() } catch {
                DispatchQueue.main.async { onError(DownloadError(message: "Failed to launch: \(error.localizedDescription)", code: "launch_failed")) }
                return
            }
            let handle = stdout.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                guard let output = String(data: data, encoding: .utf8) else { continue }
                for line in output.split(separator: "\n") {
                    guard let jsonData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let type = json["type"] as? String else { continue }
                    DispatchQueue.main.async {
                        switch type {
                        case "progress":
                            onProgress(ProgressUpdate(percent: (json["percent"] as? Double) ?? 0, downloadedBytes: json["downloaded_bytes"] as? Int64, totalBytes: json["total_bytes"] as? Int64, etaSeconds: json["eta_seconds"] as? Int))
                        case "complete":
                            onComplete(CompletionResult(filePath: json["file_path"] as? String ?? "", title: json["title"] as? String ?? "Unknown", platform: json["platform"] as? String ?? "unknown", mediaType: json["media_type"] as? String ?? "video", fileSize: json["file_size"] as? Int64 ?? 0, thumbnailPath: json["thumbnail_path"] as? String))
                        case "error":
                            onError(DownloadError(message: json["message"] as? String ?? "Unknown error", code: json["code"] as? String ?? "unknown"))
                        default: break
                        }
                    }
                }
            }
            process.waitUntilExit()
        }
    }

    private static func findPython() -> String {
        // Prefer stable Python versions over bleeding edge (3.14 has expat issues)
        let candidates = [
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "/usr/bin/python3"
    }
}
