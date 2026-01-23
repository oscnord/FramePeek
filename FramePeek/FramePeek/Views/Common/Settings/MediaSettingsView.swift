import SwiftUI

struct MediaSettingsView: View {
    @AppStorage("autoGenerateThumbnails") private var autoGenerateThumbnails: Bool = true
    @AppStorage("maxThumbnails") private var maxThumbnails: Int = 200
    @AppStorage("thumbnailSize") private var thumbnailSize: ThumbnailSize = .medium

    @AppStorage("playerAutoPlay") private var playerAutoPlay: Bool = false
    @AppStorage("playerShowControls") private var playerShowControls: Bool = true
    @AppStorage("playerShowStatistics") private var playerShowStatistics: Bool = true
    @AppStorage("playerMuted") private var playerMuted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Thumbnails") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Toggle("Auto-generate Thumbnails", isOn: $autoGenerateThumbnails)
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))

                        Text("Automatically generate thumbnails when a file loads. Disable to improve performance.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Max Thumbnails")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $maxThumbnails, in: 50...500, step: 50) {
                                Text("\(maxThumbnails)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        Text("Maximum number of thumbnails to generate. Lower values improve performance.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Picker("Thumbnail Size", selection: $thumbnailSize) {
                            ForEach(ThumbnailSize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Size of generated thumbnails. Larger sizes use more memory but provide better detail.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }

            SettingsSection(title: "Video Player") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Toggle("Auto-play", isOn: $playerAutoPlay)
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))

                        Text("Automatically start playback when the player window opens.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Toggle("Show Playback Controls", isOn: $playerShowControls)
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))

                        Text("Show play/pause and seek controls in the player window.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Toggle("Show Statistics", isOn: $playerShowStatistics)
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))

                        Text("Display real-time statistics overlay (time, bitrate, resolution, frame rate) during playback.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Toggle("Mute Video", isOn: $playerMuted)
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))

                        Text("Mute video playback by default. You can still control volume using the player controls.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
        }
    }
}
