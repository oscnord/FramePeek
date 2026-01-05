import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SamplingModeSetting: String, CaseIterable, Identifiable, Codable {
    case auto
    case interval
    case everyFrame
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return String(localized: "Automatic")
        case .interval: return String(localized: "Fixed Interval")
        case .everyFrame: return String(localized: "Every Frame")
        }
    }
}

enum FileOpeningBehavior: String, CaseIterable, Identifiable, Codable {
    case prompt
    case newTab
    case currentTab
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .prompt: return String(localized: "Prompt")
        case .newTab: return String(localized: "Always Open in New Tab")
        case .currentTab: return String(localized: "Always Overwrite Current Tab")
        }
    }
}

enum ThumbnailSize: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
    
    var cgSize: CGSize {
        switch self {
        case .small: return CGSize(width: 128, height: 80)
        case .medium: return CGSize(width: 192, height: 120)
        case .large: return CGSize(width: 256, height: 160)
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case analysis
    case media
    case display
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .general: return String(localized: "General")
        case .analysis: return String(localized: "Analysis")
        case .media: return String(localized: "Media")
        case .display: return String(localized: "Display")
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .analysis: return "chart.line.uptrend.xyaxis"
        case .media: return "photo.on.rectangle"
        case .display: return "display"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("fileOpeningBehavior") private var fileOpeningBehavior: FileOpeningBehavior = .prompt
    
    @AppStorage("samplingMode") private var samplingMode: SamplingModeSetting = .auto
    @AppStorage("samplingIntervalSeconds") private var samplingIntervalSeconds: Double = 0.5
    @AppStorage("maxPointsTarget") private var maxPointsTarget: Int = 2000
    @AppStorage("preferAccuracy") private var preferAccuracy: Bool = false
    
    @AppStorage("accountTSOverhead") private var accountTSOverhead: Bool = false
    @AppStorage("smoothSegmentBoundaries") private var smoothSegmentBoundaries: Bool = true
    @AppStorage("formatAccuracyMode") private var formatAccuracyMode: FormatAccuracyMode = .balanced
    
    // Keyframes & Thumbnails settings
    @AppStorage("autoGenerateThumbnails") private var autoGenerateThumbnails: Bool = true
    @AppStorage("maxThumbnails") private var maxThumbnails: Int = 200
    @AppStorage("thumbnailSize") private var thumbnailSize: ThumbnailSize = .medium
    
    // Chart Display settings
    @AppStorage("chartMaxDisplayPoints") private var chartMaxDisplayPoints: Int = 1_000
    @AppStorage("chartMaxDisplayPointsZoomed") private var chartMaxDisplayPointsZoomed: Int = 2_000
    @AppStorage("emitEveryNSamples") private var emitEveryNSamples: Int = 100
    
    // UI Preferences (for reset buttons)
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 380
    @AppStorage("sidebarTabBarWidth") private var sidebarTabBarWidth: Double = 200
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with tabs
            VStack(spacing: DesignSystem.Spacing.sm) {
                List(selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.displayName, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 4,
                    leading: DesignSystem.Padding.md,
                    bottom: 4,
                    trailing: DesignSystem.Padding.md
                ))
            }
            .navigationTitle("Settings")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                    Group {
                        switch selectedTab {
                        case .general:
                            generalSettings
                        case .analysis:
                            analysisSettings
                        case .media:
                            mediaSettings
                        case .display:
                            displaySettings
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.xxl2)
                .padding(.top, DesignSystem.Padding.xxl)
                .padding(.bottom, DesignSystem.Padding.xl2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
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
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Reset UI Layout")
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                        
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Button(String(localized: "Reset Sidebar Width")) {
                                sidebarTabBarWidth = 200
                            }
                            .buttonStyle(.bordered)
                            
                            Button(String(localized: "Reset Inspector Width")) {
                                inspectorWidth = 380
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("Reset panel widths to their default values.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Analysis Settings
    
    private var analysisSettings: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Analysis") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Sampling Mode")
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                        
                        Picker("", selection: $samplingMode) {
                            ForEach(SamplingModeSetting.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        
                        Text("Choose how frames are sampled for bitrate analysis.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        switch samplingMode {
                        case .auto:
                            HStack {
                                Text("Target Samples")
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Stepper(value: $maxPointsTarget, in: 500...50_000, step: 500) {
                                    Text("\(maxPointsTarget)")
                                        .monospacedDigit()
                                        .frame(minWidth: 80, alignment: .trailing)
                                }
                            }
                            
                        case .interval:
                            HStack {
                                Text("Interval")
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Stepper(value: $samplingIntervalSeconds, in: 0.05...10.0, step: 0.05) {
                                    Text("\(samplingIntervalSeconds, specifier: "%.2f") s")
                                        .monospacedDigit()
                                        .frame(minWidth: 80, alignment: .trailing)
                                }
                            }
                            
                            HStack {
                                Text("Max Samples")
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Stepper(value: $maxPointsTarget, in: 500...50_000, step: 500) {
                                    Text("\(maxPointsTarget)")
                                        .monospacedDigit()
                                        .frame(minWidth: 80, alignment: .trailing)
                                }
                            }
                            
                        case .everyFrame:
                            HStack {
                                Text("Maximum Samples")
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Stepper(value: $maxPointsTarget, in: 1_000...200_000, step: 1_000) {
                                    Text("\(maxPointsTarget)")
                                        .monospacedDigit()
                                        .frame(minWidth: 80, alignment: .trailing)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                        Text("Format-Specific Options")
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Picker("Accuracy Mode", selection: $formatAccuracyMode) {
                                    ForEach(FormatAccuracyMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                Text("Performance: Fastest, uses AVFoundation data as-is. Balanced: Format-specific optimizations. Accuracy: Full format parsing for maximum precision.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Toggle("Account for TS Packet Overhead", isOn: $accountTSOverhead)
                                    .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                                
                                Text("For MPEG-TS files: Subtract transport stream packet header overhead from bitrate calculations for more accurate video bitrate.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Toggle("Smooth Segment Boundaries", isOn: $smoothSegmentBoundaries)
                                    .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                                
                                Text("For fragmented MP4/CMAF files: Smooth bitrate spikes at segment boundaries for more consistent visualization.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Media Settings
    
    private var mediaSettings: some View {
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
        }
    }
    
    // MARK: - Display Settings
    
    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Chart Display") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Max Points (Normal)")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $chartMaxDisplayPoints, in: 500...5_000, step: 500) {
                                Text("\(chartMaxDisplayPoints)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                        
                        Text("Maximum points rendered in chart when not zoomed. Lower values improve performance.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Max Points (Zoomed)")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $chartMaxDisplayPointsZoomed, in: 1_000...10_000, step: 500) {
                                Text("\(chartMaxDisplayPointsZoomed)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                        
                        Text("Maximum points rendered when zoomed. Higher values provide more detail when zoomed in.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("UI Update Batch Size")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $emitEveryNSamples, in: 50...500, step: 50) {
                                Text("\(emitEveryNSamples)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                        
                        Text("How many samples to accumulate before updating UI. Higher values = smoother but less responsive updates.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(title)
                .font(.system(size: DesignSystem.Typography.headline, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.Semantic.primary)
            
            content
                .padding(.leading, DesignSystem.Padding.sm)
        }
    }
}

#Preview {
    SettingsView()
}

