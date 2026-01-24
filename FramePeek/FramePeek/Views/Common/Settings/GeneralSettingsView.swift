import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("fileOpeningBehavior") private var fileOpeningBehavior: FileOpeningBehavior = .prompt
    @State private var cacheSize: String = "Calculating..."
    @State private var isClearingCache = false

    private let cacheManager = CacheManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Appearance") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
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

                    Text("Choose how FramePeek should appear. 'System' follows your Mac's appearance setting.")
                        .font(.system(size: DesignSystem.Typography.footnote))
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                }
            }

            SettingsSection(title: "Interface") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("File Opening Behavior")
                                .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                            Spacer()
                            Picker("", selection: $fileOpeningBehavior) {
                                ForEach(FileOpeningBehavior.allCases) { behavior in
                                    Text(behavior.displayName).tag(behavior)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        Text("Choose what happens when you open a file while another file is already open in the current tab.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }

            SettingsSection(title: "Cache") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Cache Size")
                                .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                            Text("Waveforms and GOP analysis data are cached for faster loading.")
                                .font(.system(size: DesignSystem.Typography.footnote))
                                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                        }

                        Spacer()

                        Text(cacheSize)
                            .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button {
                            clearAllCaches()
                        } label: {
                            if isClearingCache {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Label("Clear All Caches", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isClearingCache)

                        Button {
                            clearWaveformCache()
                        } label: {
                            Text("Clear Waveforms")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isClearingCache)

                        Button {
                            clearGOPCache()
                        } label: {
                            Text("Clear GOP Data")
                        }
                        .buttonStyle(.borderless)
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

    private func clearWaveformCache() {
        isClearingCache = true
        Task {
            await cacheManager.clearWaveformCache()
            await updateCacheSize()
            isClearingCache = false
        }
    }

    private func clearGOPCache() {
        isClearingCache = true
        Task {
            await cacheManager.clearGOPCache()
            await updateCacheSize()
            isClearingCache = false
        }
    }
}
