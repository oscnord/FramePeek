import SwiftUI

// MARK: - DoviTool Status

enum DoviToolStatus {
    case unknown
    case checking
    case available(path: String)
    case notFound
    case sandboxed  // App is running in sandbox, external tools unavailable
    
    var displayText: String {
        switch self {
        case .unknown: return String(localized: "Unknown")
        case .checking: return String(localized: "Checking...")
        case .available(let path): return String(localized: "Available at \(path)")
        case .notFound: return String(localized: "Not found")
        case .sandboxed: return String(localized: "Not available in App Store version")
        }
    }
    
    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct AnalysisSettingsView: View {
    @AppStorage("samplingMode") private var samplingMode: SamplingModeSetting = .auto
    @AppStorage("samplingIntervalSeconds") private var samplingIntervalSeconds: Double = 0.5
    @AppStorage("maxPointsTarget") private var maxPointsTarget: Int = 2000

    @AppStorage("accountTSOverhead") private var accountTSOverhead: Bool = false
    @AppStorage("smoothSegmentBoundaries") private var smoothSegmentBoundaries: Bool = true
    @AppStorage("formatAccuracyMode") private var formatAccuracyMode: FormatAccuracyMode = .balanced

    @AppStorage("colorAnalysisSampleInterval") private var colorAnalysisSampleInterval: Double = 1.0
    @AppStorage("colorAnalysisMaxSamples") private var colorAnalysisMaxSamples: Int = 1000
    @AppStorage("colorAnalysisSmoothingFactor") private var colorAnalysisSmoothingFactor: Double = 0.3
    
    // Color analysis settings
    @AppStorage("waveformScale") private var waveformScale: String = WaveformScale.percentage.rawValue
    @AppStorage("vectorscopeShowReferenceBoxes") private var vectorscopeShowReferenceBoxes: Bool = true
    @AppStorage("generateWaveformData") private var generateWaveformData: Bool = true
    @AppStorage("generateVectorscopeData") private var generateVectorscopeData: Bool = true
    
    // dovi_tool settings
    @AppStorage("doviToolPath") private var doviToolPath: String = ""
    
    @State private var doviToolStatus: DoviToolStatus = .unknown
    @State private var detectedPath: String = ""
    
    /// Detects if the app is running in App Sandbox (required for App Store)
    private var isRunningInSandbox: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
            SettingsSection(title: "Bitrate Analysis") {
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

            SettingsSection(title: "Color Analysis") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Sample Interval")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $colorAnalysisSampleInterval, in: 0.1...10.0, step: 0.1) {
                                Text("\(colorAnalysisSampleInterval, specifier: "%.1f") s")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        Text("Time interval between color samples. Lower values provide more detail but take longer to analyze.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Maximum Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $colorAnalysisMaxSamples, in: 100...10_000, step: 100) {
                                Text("\(colorAnalysisMaxSamples)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        Text("Maximum number of color samples to collect. Higher values provide more detail but use more memory.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        HStack {
                            Text("Smoothing Factor")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $colorAnalysisSmoothingFactor, in: 0.0...1.0, step: 0.05) {
                                Text("\(colorAnalysisSmoothingFactor, specifier: "%.2f")")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        Text("Smoothing factor for brightness and color temperature calculations. Higher values reduce noise but may hide rapid changes.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                    
                    Divider()
                    
                    // Waveform & Vectorscope Options
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                        Text("Scopes")
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            Toggle("Generate Waveform Data", isOn: $generateWaveformData)
                                .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                            
                            if generateWaveformData {
                                HStack {
                                    Text("Default Scale")
                                        .frame(width: 140, alignment: .leading)
                                    Spacer()
                                    Picker("", selection: $waveformScale) {
                                        Text("Percentage (0-100%)").tag(WaveformScale.percentage.rawValue)
                                        Text("IRE (0-100+)").tag(WaveformScale.ire.rawValue)
                                        Text("Nits (HDR)").tag(WaveformScale.nits.rawValue)
                                        Text("Log Nits (HDR)").tag(WaveformScale.logNits.rawValue)
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 200)
                                }
                            }
                            
                            Divider()
                            
                            Toggle("Generate Vectorscope Data", isOn: $generateVectorscopeData)
                                .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                            
                            if generateVectorscopeData {
                                Toggle("Show Color Reference Boxes", isOn: $vectorscopeShowReferenceBoxes)
                            }
                        }
                        
                        Text("Waveform and vectorscope analysis provides professional color grading tools. Disable to reduce memory usage.")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
            
            // Dolby Vision Settings
            SettingsSection(title: "Dolby Vision") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                    if isRunningInSandbox {
                        // Sandboxed mode - show informational message
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: DesignSystem.Typography.body))
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("Extended Dolby Vision metadata (MaxCLL, MaxFALL, etc.) is not available in the App Store version.")
                                    .font(.system(size: DesignSystem.Typography.body))
                                
                                Text("Basic Dolby Vision detection (profile, level, compatibility) works without external tools.")
                                    .font(.system(size: DesignSystem.Typography.footnote))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        // Non-sandboxed mode - show full dovi_tool UI
                        Text("dovi_tool")
                            .font(.system(size: DesignSystem.Typography.body, weight: .medium))
                        
                        // Path field with status and actions
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            // Path display (shows detected or manual path)
                            TextField(
                                String(localized: "Path to dovi_tool"),
                                text: Binding(
                                    get: { doviToolPath.isEmpty ? detectedPath : doviToolPath },
                                    set: { doviToolPath = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(doviToolPath.isEmpty && !detectedPath.isEmpty ? .secondary : .primary)
                            
                            // Auto-detect button
                            Button {
                                autoDetectDoviTool()
                            } label: {
                                Image(systemName: "sparkle.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Auto-detect dovi_tool"))
                            
                            // Browse button
                            Button {
                                browseForDoviTool()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Browse for dovi_tool"))
                        }
                        
                        // Status message
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            switch doviToolStatus {
                            case .unknown:
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                Text("Click auto-detect to find dovi_tool")
                                    .foregroundStyle(.secondary)
                            case .checking:
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Searching...")
                                    .foregroundStyle(.secondary)
                            case .available(let path):
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Found at \(path)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            case .notFound:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("Not found. Install via: brew install quietvoid/dovi_tool/dovi_tool")
                                    .foregroundStyle(.secondary)
                            case .sandboxed:
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                Text("Not available in sandboxed environment")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: DesignSystem.Typography.footnote))
                        
                        Text("dovi_tool is an optional utility for detailed Dolby Vision metadata (MaxCLL, MaxFALL, etc.).")
                            .font(.system(size: DesignSystem.Typography.footnote))
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
        }
        .onAppear {
            checkDoviToolStatus()
        }
    }
    
    // MARK: - Helper Methods
    
    private func autoDetectDoviTool() {
        doviToolStatus = .checking
        doviToolPath = ""  // Clear manual path when auto-detecting
        DoviToolManager.shared.resetCache()
        
        Task {
            // Small delay for UI feedback
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            if let path = DoviToolManager.shared.findDoviTool() {
                await MainActor.run {
                    detectedPath = path
                    doviToolStatus = .available(path: path)
                }
            } else {
                await MainActor.run {
                    detectedPath = ""
                    doviToolStatus = .notFound
                }
            }
        }
    }
    
    private func checkDoviToolStatus() {
        doviToolStatus = .checking
        
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            // If user has set a manual path, verify it
            if !doviToolPath.isEmpty {
                let expandedPath = NSString(string: doviToolPath).expandingTildeInPath
                if FileManager.default.isExecutableFile(atPath: expandedPath) {
                    await MainActor.run {
                        doviToolStatus = .available(path: expandedPath)
                    }
                    return
                }
            }
            
            // Otherwise try to find it
            if let path = DoviToolManager.shared.findDoviTool() {
                await MainActor.run {
                    detectedPath = path
                    doviToolStatus = .available(path: path)
                }
            } else {
                await MainActor.run {
                    detectedPath = ""
                    doviToolStatus = .notFound
                }
            }
        }
    }
    
    private func browseForDoviTool() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = String(localized: "Select dovi_tool executable")
        panel.prompt = String(localized: "Select")
        
        if panel.runModal() == .OK, let url = panel.url {
            doviToolPath = url.path
            detectedPath = ""  // Clear detected path when manually selecting
            DoviToolManager.shared.resetCache()
            checkDoviToolStatus()
        }
    }
}
