import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage("chartMaxDisplayPoints") private var chartMaxDisplayPoints: Int = 1_000
    @AppStorage("chartMaxDisplayPointsZoomed") private var chartMaxDisplayPointsZoomed: Int = 2_000
    @AppStorage("emitEveryNSamples") private var emitEveryNSamples: Int = 100

    var body: some View {
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
