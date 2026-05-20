import SwiftUI

struct ProgressSection: View {
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading from \(platformName)...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(Int(item.progress))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.08))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, Color(red: 0.38, green: 0.65, blue: 0.98)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0, min(item.progress / 100, 1)), height: 4)
                        .shadow(color: .blue.opacity(0.4), radius: 4)
                }
            }
            .frame(height: 4)
            HStack {
                if let downloaded = item.downloadedBytes, let total = item.totalBytes, total > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                }
                if let eta = item.etaSeconds, eta > 0 {
                    Text("\u{00B7} ~\(eta)s remaining")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.blue.opacity(0.06))
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
