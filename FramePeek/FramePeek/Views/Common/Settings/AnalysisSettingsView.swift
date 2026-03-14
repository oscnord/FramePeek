import SwiftUI
import FramePeekCore

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
    
    // Scope settings
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
                        Picker("Sampling Mode", selection: $samplingMode) {
                            ForEach(SamplingModeSetting.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
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

                    Picker("Accuracy Mode", selection: $formatAccuracyMode) {
                        ForEach(FormatAccuracyMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Divider()

                    Toggle("Account for TS Packet Overhead", isOn: $accountTSOverhead)

                    Toggle("Smooth Segment Boundaries", isOn: $smoothSegmentBoundaries)
                }
            }

            SettingsSection(title: "Color Analysis") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
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

                    Divider()

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
                    
                    Divider()
                    
                    // Waveform & Vectorscope
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Toggle("Generate Waveform", isOn: $generateWaveformData)
                        
                        if generateWaveformData {
                            Picker("Waveform Scale", selection: $waveformScale) {
                                Text("Percentage (0-100%)").tag(WaveformScale.percentage.rawValue)
                                Text("IRE (0-100+)").tag(WaveformScale.ire.rawValue)
                                Text("Nits (HDR)").tag(WaveformScale.nits.rawValue)
                                Text("Log Nits (HDR)").tag(WaveformScale.logNits.rawValue)
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Divider()
                        
                        Toggle("Generate Vectorscope", isOn: $generateVectorscopeData)
                        
                        if generateVectorscopeData {
                            Toggle("Show Reference Boxes", isOn: $vectorscopeShowReferenceBoxes)
                                .padding(.leading, DesignSystem.Padding.lg)
                        }
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
            try? await Task.sleep(for: .milliseconds(200))
            
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
            try? await Task.sleep(for: .milliseconds(100))
            
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
