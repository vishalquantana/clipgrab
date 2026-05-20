import SwiftUI

struct SetupAssistantView: View {
    @State private var ytdlpInstalled = false
    @State private var ffmpegInstalled = false
    @State private var checking = true
    @State private var installing = false
    @State private var installLog = ""
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to ClipGrab")
                .font(.title.bold())

            Text("ClipGrab needs yt-dlp and ffmpeg to download and convert media. Let's check if they're installed.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                DependencyRow(name: "yt-dlp", installed: ytdlpInstalled, checking: checking)
                DependencyRow(name: "ffmpeg", installed: ffmpegInstalled, checking: checking)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))

            if !checking {
                if ytdlpInstalled && ffmpegInstalled {
                    Button("Get Started") { onComplete() }
                        .buttonStyle(.borderedProminent)
                } else {
                    VStack(spacing: 12) {
                        Button(installing ? "Installing..." : "Install via Homebrew") { installDependencies() }
                            .buttonStyle(.borderedProminent)
                            .disabled(installing)

                        if installing || !installLog.isEmpty {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    Text(installLog.isEmpty ? "Starting installation..." : installLog)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id("logBottom")
                                }
                                .frame(height: 120)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.3)))
                                .onChange(of: installLog) { _ in
                                    proxy.scrollTo("logBottom", anchor: .bottom)
                                }
                            }
                        }

                        Text("Requires Homebrew. Run in Terminal:\nbrew install yt-dlp ffmpeg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(40)
        .frame(width: 420)
        .onAppear { checkDependencies() }
    }

    private func checkDependencies() {
        checking = true
        DispatchQueue.global().async {
            let ytdlp = Self.commandExists("yt-dlp")
            let ffmpeg = Self.commandExists("ffmpeg")
            DispatchQueue.main.async {
                ytdlpInstalled = ytdlp
                ffmpegInstalled = ffmpeg
                checking = false
            }
        }
    }

    private func installDependencies() {
        installing = true
        installLog = ""
        DispatchQueue.global().async {
            let brewPath = Self.findBrew()
            guard let brewPath else {
                DispatchQueue.main.async {
                    installLog = "Error: Homebrew not found.\nInstall it first: https://brew.sh\n\nRun in Terminal:\n/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    installing = false
                }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "\(brewPath) install yt-dlp ffmpeg 2>&1"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    installLog += line
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    installLog += "\nFailed to run brew: \(error.localizedDescription)"
                }
            }

            pipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                installing = false
                if process.terminationStatus == 0 {
                    installLog += "\n\nInstallation complete!"
                } else {
                    installLog += "\n\nInstallation failed (exit code \(process.terminationStatus))"
                }
                checkDependencies()
            }
        }
    }

    private static func findBrew() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func commandExists(_ name: String) -> Bool {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return false
    }
}

struct DependencyRow: View {
    let name: String
    let installed: Bool
    let checking: Bool

    var body: some View {
        HStack {
            if checking {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(installed ? .green : .red)
                    .frame(width: 20, height: 20)
            }
            Text(name)
                .font(.system(size: 14, design: .monospaced))
            Spacer()
            Text(checking ? "Checking..." : (installed ? "Installed" : "Not found"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
