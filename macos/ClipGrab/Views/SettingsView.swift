import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ClipGrab Settings")
                .font(.title2.bold())

            GroupBox("Download Location") {
                HStack {
                    Text(settings.downloadFolder)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.downloadFolder = url.path
                        }
                    }
                }
                .padding(4)
            }

            GroupBox("Media Type") {
                Picker("Download", selection: $settings.mediaType) {
                    Text("All media (videos + photos)").tag("all")
                    Text("Videos only").tag("videos_only")
                }
                .pickerStyle(.radioGroup)
                .padding(4)
            }

            GroupBox("Monitored Platforms") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Instagram", isOn: platformBinding("instagram"))
                    Toggle("Twitter/X", isOn: platformBinding("twitter"))
                    Toggle("LinkedIn", isOn: platformBinding("linkedin"))
                }
                .padding(4)
            }

            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-copy downloaded media to clipboard", isOn: $settings.autoCopyToClipboard)
                    Toggle("Show notifications", isOn: $settings.notificationsEnabled)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    HStack {
                        Text("History limit:")
                        Picker("", selection: $settings.historyLimit) {
                            Text("10").tag(10)
                            Text("25").tag(25)
                            Text("50").tag(50)
                            Text("100").tag(100)
                            Text("Unlimited").tag(0)
                        }
                        .frame(width: 120)
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Done") {
                    settings.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private func platformBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledPlatforms[id] ?? true },
            set: { settings.enabledPlatforms[id] = $0 }
        )
    }
}
