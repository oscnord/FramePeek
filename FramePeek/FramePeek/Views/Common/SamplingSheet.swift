import SwiftUI

struct SamplingSheet: View {
    @ObservedObject var viewModel: FramePeekViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm3) {
                Text("Analysis Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg3) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Sampling Mode")
                        .font(.headline)
                    
                    Picker("", selection: $viewModel.samplingMode) {
                        Text("Automatic").tag(FramePeekViewModel.SamplingMode.auto)
                        Text("Fixed Interval").tag(FramePeekViewModel.SamplingMode.interval)
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
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
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Materials.regular)
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Toggle(isOn: $viewModel.preferAccuracy) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("High Accuracy")
                            .font(.headline)
                        Text("More accurate bitrate measurements (may be slower)")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Materials.regular)
            }

            Spacer()

            Text("You can disable this dialog in Settings (⌘,)")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, DesignSystem.Padding.sm)

            HStack {
                Button("Cancel") {
                    viewModel.cancelSamplingDialog()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Analyze") {
                    viewModel.confirmSamplingAndLoad()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Padding.xl)
        .frame(minWidth: 420, minHeight: 300)
        .onDisappear {
            if viewModel.showSamplingDialog || viewModel.pendingURL != nil {
                viewModel.cancelSamplingDialog()
            }
        }
    }
}

