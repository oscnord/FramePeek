import SwiftUI
import FramePeekCore

struct GeneralSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("fileOpeningBehavior") private var fileOpeningBehavior: FileOpeningBehavior = .prompt
    @State private var cacheSize: String = "Calculating..."
    @State private var isClearingCache = false

    private let cacheManager = CacheManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Appearance") {
                Picker("", selection: Binding(
                    get: { appearanceMode },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appearanceMode = newValue
                        }
                    }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsSection(title: "File Handling") {
                Picker("When opening files", selection: $fileOpeningBehavior) {
                    ForEach(FileOpeningBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .pickerStyle(.menu)
            }

            SettingsSection(title: "Cache") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Text("Waveforms and GOP analysis data are cached locally for faster loading.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text("Size")
                        Spacer()
                        Text(cacheSize)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        
                        Button {
                            clearAllCaches()
                        } label: {
                            if isClearingCache {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Clear")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearingCache)
                    }
                }
            }
        }
        .task {
            await updateCacheSize()
        }
    }

    private func updateCacheSize() async {
        await cacheManager.recalculateCacheSize()
        cacheSize = cacheManager.formattedCacheSize
    }

    private func clearAllCaches() {
        isClearingCache = true
        Task {
            await cacheManager.clearAllCaches()
            await updateCacheSize()
            isClearingCache = false
        }
    }
}
