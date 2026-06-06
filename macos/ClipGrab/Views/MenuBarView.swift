import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var downloadQueue: DownloadQueue
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateManager = UpdateManager.shared
    @State private var showSettings = false
    @State private var pasteURL = ""
    @State private var showPasteField = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isDownloading ? .blue : .green)
                HStack(spacing: 4) {
                    Text("ClipGrab")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\u{00B7}")
                        .foregroundColor(.white.opacity(0.4))
                    Text(statusText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showPasteField.toggle() } }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(showPasteField ? 0.6 : 0.3))
                }
                .buttonStyle(.plain)
                .help("Paste a URL to download")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.03))

            Divider().background(.white.opacity(0.06))

            // Paste URL field
            if showPasteField {
                HStack(spacing: 8) {
                    TextField("Paste a URL...", text: $pasteURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                        .onSubmit { submitURL() }
                    Button(action: submitURL) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(pasteURL.isEmpty ? .white.opacity(0.2) : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(pasteURL.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().background(.white.opacity(0.06))
            }

            // Update Banner
            if updateManager.isUpdateAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Available (v\(updateManager.latestVersion ?? ""))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                        if let err = updateManager.errorMessage {
                            Text(err)
                                .font(.system(size: 9))
                                .foregroundColor(.red.opacity(0.8))
                        } else if updateManager.isUpdating {
                            ProgressView(value: updateManager.updateProgress)
                                .progressViewStyle(.linear)
                                .tint(.orange)
                                .frame(width: 150)
                        } else {
                            Text("A new version is ready to install.")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    Button(action: { updateManager.startUpdate() }) {
                        Text(updateManager.isUpdating ? "\(Int(updateManager.updateProgress * 100))%" : "Update")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(updateManager.isUpdating)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
                Divider().background(.white.opacity(0.06))
            }

            if let current = downloadQueue.currentDownload {
                ProgressSection(item: current)
                Divider().background(.white.opacity(0.06))
            }

            if !downloadQueue.history.isEmpty {
                HStack {
                    Text("RECENT DOWNLOADS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(downloadQueue.history.prefix(5)) { item in
                        DownloadItemRow(
                            item: item,
                            onCopy: { downloadQueue.copyToClipboard(item) },
                            onCopyAudio: { completion in downloadQueue.copyAudioToClipboard(item, completion: completion) }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            if downloadQueue.history.isEmpty && downloadQueue.currentDownload == nil {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Copy a social media link to get started")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }

            // Credits
            HStack(spacing: 0) {
                Text("Made with ")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                Image(systemName: "heart.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.red.opacity(0.4))
                Text(" by ")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                Link("Quantana", destination: URL(string: "https://quantana.com.au")!)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Divider().background(.white.opacity(0.06))

            HStack {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                        .font(.system(size: 12))
                        .foregroundColor(.blue.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: openDownloadsFolder) {
                    Label("Folder", systemImage: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isDownloading ? .blue : .green)
                        .frame(width: 6, height: 6)
                        .shadow(color: isDownloading ? .blue.opacity(0.5) : .green.opacity(0.5), radius: 3)
                    Text(isDownloading ? "Downloading" : "Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isDownloading ? .blue.opacity(0.9) : .green.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isDownloading ? .blue.opacity(0.08) : .green.opacity(0.08))
                        .overlay(Capsule().stroke(isDownloading ? .blue.opacity(0.15) : .green.opacity(0.15)))
                )

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.15))
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    private var isDownloading: Bool {
        downloadQueue.currentDownload != nil
    }

    private var statusText: String {
        if downloadQueue.currentDownload != nil {
            if downloadQueue.queueCount > 0 {
                return "Downloading (+\(downloadQueue.queueCount) queued)"
            }
            return "Downloading..."
        }
        return "Watching clipboard"
    }

    private func submitURL() {
        let url = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, url.hasPrefix("http") else { return }
        downloadQueue.enqueue(url: url, platform: detectPlatform(url))
        pasteURL = ""
        withAnimation { showPasteField = false }
    }

    private func detectPlatform(_ url: String) -> String {
        let patterns: [(String, String)] = [
            ("instagram", "instagram.com"),
            ("youtube", "youtube.com"), ("youtube", "youtu.be"),
            ("tiktok", "tiktok.com"),
            ("twitter", "twitter.com"), ("twitter", "x.com"),
            ("reddit", "reddit.com"), ("reddit", "redd.it"),
            ("facebook", "facebook.com"), ("facebook", "fb.watch"),
            ("threads", "threads.net"),
            ("vimeo", "vimeo.com"),
            ("pinterest", "pinterest.com"),
            ("twitch", "twitch.tv"),
            ("linkedin", "linkedin.com"),
            ("9gag", "9gag.com"),
        ]
        let lower = url.lowercased()
        for (platform, domain) in patterns {
            if lower.contains(domain) { return platform }
        }
        return "unknown"
    }

    private func openDownloadsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: settings.downloadFolder))
    }
}
