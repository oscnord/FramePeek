//
//  SettingsView.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
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
        case .auto: return "Automatic"
        case .interval: return "Fixed Interval"
        case .everyFrame: return "Every Frame"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("showInspector") private var showInspector: Bool = false
    @AppStorage("showSettingsOnFileLoad") private var showSettingsOnFileLoad: Bool = true
    
    // Analysis settings
    @AppStorage("samplingMode") private var samplingMode: SamplingModeSetting = .auto
    @AppStorage("samplingIntervalSeconds") private var samplingIntervalSeconds: Double = 0.5
    @AppStorage("maxPointsTarget") private var maxPointsTarget: Int = 2000
    @AppStorage("preferAccuracy") private var preferAccuracy: Bool = false
    @AppStorage("visualizationMode") private var visualizationMode: BitrateVisualizationMode = .second
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 20)
            }
            .padding(.bottom, 24)
            
            Divider()
                .padding(.horizontal, 40)
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Appearance section
                    SettingsSection(title: "Appearance") {
                        VStack(alignment: .leading, spacing: 16) {
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Interface section
                    SettingsSection(title: "Interface") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Show Inspector by Default", isOn: $showInspector)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text("When enabled, the inspector panel will be visible when you open a new file.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Show Settings When Loading Files", isOn: $showSettingsOnFileLoad)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text("When enabled, analysis settings will be shown when you load a new file. You can always adjust settings in Settings.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Analysis section
                    SettingsSection(title: "Analysis") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sampling Mode")
                                    .font(.system(size: 14, weight: .medium))
                                
                                Picker("", selection: $samplingMode) {
                                    ForEach(SamplingModeSetting.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                
                                Text("Choose how frames are sampled for bitrate analysis.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 12) {
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
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Visualization Mode", selection: $visualizationMode) {
                                    ForEach(BitrateVisualizationMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                Text("How bitrate is aggregated: per second, per frame, or per GOP.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $preferAccuracy) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("High Accuracy")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("More accurate bitrate measurements (may be slower)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 40)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
            .padding(.bottom, 24)
        }
        .frame(minHeight: 500, maxHeight: 700)
        .background(.background)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            content
                .padding(.leading, 4)
        }
    }
}

#Preview {
    SettingsView()
}

