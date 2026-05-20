import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var downloadQueue: DownloadQueue
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false

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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.03))

            Divider().background(.white.opacity(0.06))

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
                        DownloadItemRow(item: item) {
                            downloadQueue.copyToClipboard(item)
                        }
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

    private func openDownloadsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: settings.downloadFolder))
    }
}
