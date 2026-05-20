import SwiftUI

struct SetupAssistantView: View {
    @State private var ytdlpInstalled = false
    @State private var ffmpegInstalled = false
    @State private var checking = true
    @State private var installing = false
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
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "brew install yt-dlp ffmpeg"]
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async {
                installing = false
                checkDependencies()
            }
        }
    }

    private static func commandExists(_ name: String) -> Bool {
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
