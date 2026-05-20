import SwiftUI

struct DownloadItemRow: View {
    let item: DownloadItem
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(platformGradient)
                    .frame(width: 52, height: 38)
                if item.mediaType == .video || item.mediaType == nil {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.status == .complete {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
            } else if item.status == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var platformGradient: LinearGradient {
        switch item.platform {
        case "instagram":
            return LinearGradient(colors: [.purple, .red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "twitter":
            return LinearGradient(colors: [Color(red: 0.1, green: 0.55, blue: 0.85), Color(red: 0.11, green: 0.63, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "linkedin":
            return LinearGradient(colors: [Color(red: 0, green: 0.26, blue: 0.51), Color(red: 0, green: 0.47, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var platformName: String {
        switch item.platform {
        case "instagram": return "Instagram"
        case "twitter": return "Twitter/X"
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
