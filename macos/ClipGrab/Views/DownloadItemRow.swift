import SwiftUI
import AVKit

struct VideoThumbnailView: NSViewRepresentable {
    let filePath: String
    let isHovering: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let url = URL(fileURLWithPath: filePath)
        let player = AVPlayer(url: url)
        player.isMuted = true
        playerView.player = player

        // Seek to 1s for a good thumbnail frame
        player.seek(to: CMTime(seconds: 1, preferredTimescale: 600))
        player.pause()

        context.coordinator.playerView = playerView
        context.coordinator.player = player

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let player = context.coordinator.player else { return }
        if isHovering {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
            player.seek(to: CMTime(seconds: 1, preferredTimescale: 600))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var playerView: AVPlayerView?
        var player: AVPlayer?
    }
}

struct DownloadItemRow: View {
    let item: DownloadItem
    let onCopy: () -> Void
    @State private var showCopied = false
    @State private var showLinkCopied = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail / video preview
            ZStack {
                if let thumbPath = item.thumbnailPath, FileManager.default.fileExists(atPath: thumbPath) {
                    // Show real thumbnail, play video on hover
                    if isHovering, item.mediaType == .video, let filePath = item.filePath, FileManager.default.fileExists(atPath: filePath) {
                        VideoThumbnailView(filePath: filePath, isHovering: isHovering)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if let nsImage = NSImage(contentsOfFile: thumbPath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                // Play icon overlay for videos
                                Group {
                                    if item.mediaType == .video {
                                        Circle()
                                            .fill(.black.opacity(0.45))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.white)
                                                    .offset(x: 1)
                                            )
                                    }
                                }
                            )
                    } else {
                        fallbackThumbnail
                    }
                } else {
                    fallbackThumbnail
                }
            }
            .frame(width: 56, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(platformName)
                    Text("\u{00B7}")
                    Text(item.createdAt.timeAgo)
                    if let size = item.fileSize, size > 0 {
                        Text("\u{00B7}")
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

                if showCopied {
                    Text("Copied to clipboard!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green.opacity(0.8))
                        .transition(.opacity)
                } else if showLinkCopied {
                    Text("Link copied!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue.opacity(0.8))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.status == .complete {
                Button(action: copyLink) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .help("Copy original URL")

                Button(action: copyMedia) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 28)
                .help("Copy media to clipboard")
            } else if item.status == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .animation(.easeInOut(duration: 0.2), value: showLinkCopied)
    }

    @ViewBuilder
    private var fallbackThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(platformGradient)
                .frame(width: 56, height: 42)
            if item.mediaType == .video {
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.black)
                            .offset(x: 1)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private func copyMedia() {
        onCopy()
        showCopied = true
        showLinkCopied = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            showCopied = false
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url, forType: .string)
        showLinkCopied = true
        showCopied = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            showLinkCopied = false
        }
    }

    private var platformGradient: LinearGradient {
        switch item.platform {
        case "instagram":
            return LinearGradient(colors: [.purple, .red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "youtube":
            return LinearGradient(colors: [Color(red: 0.9, green: 0.1, blue: 0.1), Color(red: 0.8, green: 0.0, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "tiktok":
            return LinearGradient(colors: [Color(red: 0.0, green: 0.96, blue: 0.84), .black, Color(red: 1.0, green: 0.2, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "twitter":
            return LinearGradient(colors: [Color(red: 0.1, green: 0.55, blue: 0.85), Color(red: 0.11, green: 0.63, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "reddit":
            return LinearGradient(colors: [Color(red: 1.0, green: 0.27, blue: 0.0), Color(red: 0.9, green: 0.2, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "facebook":
            return LinearGradient(colors: [Color(red: 0.06, green: 0.34, blue: 0.8), Color(red: 0.1, green: 0.4, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "threads":
            return LinearGradient(colors: [.black, Color(red: 0.3, green: 0.3, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "vimeo":
            return LinearGradient(colors: [Color(red: 0.1, green: 0.72, blue: 0.87), Color(red: 0.0, green: 0.6, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "pinterest":
            return LinearGradient(colors: [Color(red: 0.9, green: 0.0, blue: 0.15), Color(red: 0.75, green: 0.0, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "twitch":
            return LinearGradient(colors: [Color(red: 0.57, green: 0.27, blue: 1.0), Color(red: 0.45, green: 0.15, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "linkedin":
            return LinearGradient(colors: [Color(red: 0, green: 0.26, blue: 0.51), Color(red: 0, green: 0.47, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var platformName: String {
        switch item.platform {
        case "instagram": return "Instagram"
        case "youtube": return "YouTube"
        case "tiktok": return "TikTok"
        case "twitter": return "Twitter/X"
        case "reddit": return "Reddit"
        case "facebook": return "Facebook"
        case "threads": return "Threads"
        case "vimeo": return "Vimeo"
        case "pinterest": return "Pinterest"
        case "twitch": return "Twitch"
        case "linkedin": return "LinkedIn"
        default: return item.platform.capitalized
        }
    }
}

extension Date {
    var timeAgo: String {
        let interval = -timeIntervalSinceNow
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hr ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
