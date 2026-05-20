import Foundation

struct PlatformPattern: Codable, Identifiable {
    let name: String
    let id: String
    let patterns: [String]

    func matches(_ url: String) -> Bool {
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(url.startIndex..., in: url)
                if regex.firstMatch(in: url, options: [], range: range) != nil {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }
}

struct PlatformPatterns: Codable {
    let platforms: [PlatformPattern]

    static func loadDefault() -> PlatformPatterns? {
        guard let url = Bundle.main.url(forResource: "DefaultPlatforms", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(PlatformPatterns.self, from: data)
        } catch {
            return nil
        }
    }

    static func load() -> PlatformPatterns {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let clipgrabDir = appSupportDir.appendingPathComponent("ClipGrab")
        let platformsFile = clipgrabDir.appendingPathComponent("platforms.json")

        if fileManager.fileExists(atPath: platformsFile.path) {
            do {
                let data = try Data(contentsOf: platformsFile)
                let decoder = JSONDecoder()
                return try decoder.decode(PlatformPatterns.self, from: data)
            } catch {
                return loadDefault() ?? PlatformPatterns(platforms: [])
            }
        } else {
            if !fileManager.fileExists(atPath: clipgrabDir.path) {
                try? fileManager.createDirectory(at: clipgrabDir, withIntermediateDirectories: true)
            }

            if let defaultPatterns = loadDefault() {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(defaultPatterns)
                    try data.write(to: platformsFile)
                } catch {
                    return defaultPatterns
                }
                return defaultPatterns
            }

            return PlatformPatterns(platforms: [])
        }
    }

    func matchingPlatform(for url: String) -> PlatformPattern? {
        return platforms.first { $0.matches(url) }
    }
}
