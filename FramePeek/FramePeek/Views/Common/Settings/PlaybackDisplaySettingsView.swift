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
    @AppStorage("playerSafeAreaGuides") private var safeAreaGuidesRaw: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Video Player") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Toggle("Auto-play", isOn: $playerAutoPlay)
                    
                    Toggle("Show Playback Controls", isOn: $playerShowControls)
                    
                    Toggle("Show Statistics Overlay", isOn: $playerShowStatistics)
                    
                    Toggle("Mute by Default", isOn: $playerMuted)
                    
                    Divider()
                    
                    safeAreaGuidesSection
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
            
            keyboardShortcutsSection
        }
    }
    
    // MARK: - Safe Area Guides Section
    
    private var activeSafeAreaGuides: Set<SafeAreaGuideType> {
        get { Set(storageString: safeAreaGuidesRaw) }
        nonmutating set { safeAreaGuidesRaw = newValue.storageString }
    }
    
    private var safeAreaGuidesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Safe Area Guides")
                Spacer()
                if !activeSafeAreaGuides.isEmpty {
                    Button("Clear All") {
                        safeAreaGuidesRaw = ""
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            
            Text("Select guides to display over the video player")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(SafeAreaGuideType.allCases) { guide in
                    Toggle(guide.displayName, isOn: Binding(
                        get: { activeSafeAreaGuides.contains(guide) },
                        set: { isOn in
                            var guides = activeSafeAreaGuides
                            if isOn {
                                guides.insert(guide)
                            } else {
                                guides.remove(guide)
                            }
                            safeAreaGuidesRaw = guides.storageString
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Keyboard Shortcuts Section
    
    private var keyboardShortcutsSection: some View {
        SettingsSection(title: "Keyboard Shortcuts") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                shortcutRow(keys: ["←"], description: "Step back one frame")
                shortcutRow(keys: ["→"], description: "Step forward one frame")
                shortcutRow(keys: ["G"], description: "Toggle safe area guides menu")
            }
        }
    }
    
    private func shortcutRow(keys: [String], description: String) -> some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                                )
                        }
                }
            }
            .frame(width: 50, alignment: .leading)
            
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}
