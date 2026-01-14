import SwiftUI

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
                }
            }
        }
    }
}



