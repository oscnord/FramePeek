//
//  SamplingSheet.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI

struct SamplingSheet: View {
    @ObservedObject var viewModel: FramePeekViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Analysis Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sampling Mode")
                        .font(.headline)
                    
                    Picker("", selection: $viewModel.samplingMode) {
                        Text("Automatic").tag(FramePeekViewModel.SamplingMode.auto)
                        Text("Fixed Interval").tag(FramePeekViewModel.SamplingMode.interval)
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    switch viewModel.samplingMode {
                    case .auto:
                        HStack {
                            Text("Target Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                    case .interval:
                        HStack {
                            Text("Interval")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.samplingIntervalSeconds, in: 0.05...10.0, step: 0.05) {
                                Text("\(viewModel.samplingIntervalSeconds, specifier: "%.2f") s")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        HStack {
                            Text("Max Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                    case .everyFrame:
                        HStack {
                            Text("Maximum Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 1_000...200_000, step: 1_000) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $viewModel.preferAccuracy) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High Accuracy")
                            .font(.headline)
                        Text("More accurate bitrate measurements (may be slower)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }

            Spacer()

            Text("You can disable this dialog in Settings (⌘,)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            HStack {
                Button("Cancel") {
                    viewModel.cancelSamplingDialog()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Analyze") {
                    viewModel.confirmSamplingAndLoad()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 300)
    }
}

