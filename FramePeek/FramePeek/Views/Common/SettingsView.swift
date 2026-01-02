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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showInspector") private var showInspector: Bool = false
    @AppStorage("showSettingsOnFileLoad") private var showSettingsOnFileLoad: Bool = true
    @AppStorage("fileOpeningBehavior") private var fileOpeningBehavior: FileOpeningBehavior = .prompt
    
    @AppStorage("samplingMode") private var samplingMode: SamplingModeSetting = .auto
    @AppStorage("samplingIntervalSeconds") private var samplingIntervalSeconds: Double = 0.5
    @AppStorage("maxPointsTarget") private var maxPointsTarget: Int = 2000
    @AppStorage("preferAccuracy") private var preferAccuracy: Bool = false
    
    @AppStorage("accountTSOverhead") private var accountTSOverhead: Bool = false
    @AppStorage("smoothSegmentBoundaries") private var smoothSegmentBoundaries: Bool = true
    @AppStorage("formatAccuracyMode") private var formatAccuracyMode: FormatAccuracyMode = .balanced
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("Settings")
                    .font(.system(size: DesignSystem.Typography.title1, weight: .bold))
                    .padding(.top, DesignSystem.Padding.xl)
            }
            .padding(.bottom, DesignSystem.Padding.xl2)
            
            Divider()
                .padding(.horizontal, DesignSystem.Padding.xxl2)
            
            ScrollView {
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
                                Toggle("Show Inspector by Default", isOn: $showInspector)
                                    .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                                
                                Text("When enabled, the inspector panel will be visible when you open a new file.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Toggle("Show Settings When Loading Files", isOn: $showSettingsOnFileLoad)
                                    .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                                
                                Text("When enabled, analysis settings will be shown when you load a new file. You can always adjust settings in Settings.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                HStack {
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
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                Toggle(isOn: $preferAccuracy) {
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                        Text("High Accuracy")
                                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                                        Text("More accurate bitrate measurements (may be slower)")
                                            .font(.system(size: DesignSystem.Typography.footnote))
                                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
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
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                                .fill(DesignSystem.Materials.regular)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.xxl2)
                .padding(.top, DesignSystem.Padding.xxl)
                .padding(.bottom, DesignSystem.Padding.xl2)
            }
            
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Divider()
                    .padding(.horizontal, DesignSystem.Padding.xxl2)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, DesignSystem.Padding.lg)
            }
            .padding(.bottom, DesignSystem.Padding.xl2)
        }
        .frame(minHeight: 500, maxHeight: 700)
        .background(.background)
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
