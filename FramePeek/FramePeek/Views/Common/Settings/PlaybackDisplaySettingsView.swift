import SwiftUI

struct PlaybackDisplaySettingsView: View {
    // Thumbnail settings
    @AppStorage("autoGenerateThumbnails") private var autoGenerateThumbnails: Bool = true
    @AppStorage("maxThumbnails") private var maxThumbnails: Int = 200
    @AppStorage("thumbnailSize") private var thumbnailSize: ThumbnailSize = .medium

    // Player settings
    @AppStorage("playerAutoPlay") private var playerAutoPlay: Bool = false
    @AppStorage("playerShowControls") private var playerShowControls: Bool = true
    @AppStorage("playerShowStatistics") private var playerShowStatistics: Bool = true
    @AppStorage("playerMuted") private var playerMuted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Video Player") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Toggle("Auto-play", isOn: $playerAutoPlay)
                    
                    Toggle("Show Playback Controls", isOn: $playerShowControls)
                    
                    Toggle("Show Statistics Overlay", isOn: $playerShowStatistics)
                    
                    Toggle("Mute by Default", isOn: $playerMuted)
                }
            }

            SettingsSection(title: "Thumbnails") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    Toggle("Auto-generate Thumbnails", isOn: $autoGenerateThumbnails)

                    Divider()

                    HStack {
                        Text("Maximum Count")
                            .frame(width: 140, alignment: .leading)
                        Spacer()
                        Stepper(value: $maxThumbnails, in: 50...500, step: 50) {
                            Text("\(maxThumbnails)")
                                .monospacedDigit()
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }

                    Divider()

                    Picker("Size", selection: $thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
}
