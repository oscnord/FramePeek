import SwiftUI
import Charts
import FramePeekCore

/// EBU R128 loudness readout: integrated LUFS, true peak, loudness range,
/// with a short-term loudness chart
struct LoudnessCard: View {
    var viewModel: FramePeekViewModel

    @State private var cachedDisplaySamples: [LoudnessSample] = []
    @State private var lastDisplaySamplesCount: Int = 0

    private let maxDisplayPoints = 500

    private func recomputeDisplaySamples() {
        let count = viewModel.shortTermLoudness.count
        guard count != lastDisplaySamplesCount else { return }
        lastDisplaySamplesCount = count
        cachedDisplaySamples = downsampleLTTB(
            viewModel.shortTermLoudness,
            targetCount: maxDisplayPoints,
            x: { $0.time },
            y: { $0.lufs }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Loudness (EBU R128)")
                    .font(.headline)

                if viewModel.isAnalyzingLoudness {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }

            HStack(spacing: DesignSystem.Spacing.xl) {
                metric(
                    title: String(localized: "Integrated"),
                    value: viewModel.loudnessResult?.integratedLUFS,
                    unit: "LUFS",
                    compliant: viewModel.loudnessResult?.isR128Compliant
                )
                metric(
                    title: String(localized: "True Peak"),
                    value: viewModel.loudnessResult?.truePeakDBTP,
                    unit: "dBTP",
                    compliant: viewModel.loudnessResult?.isTruePeakCompliant
                )
                metric(
                    title: String(localized: "Range"),
                    value: viewModel.loudnessResult?.loudnessRangeLU,
                    unit: "LU",
                    compliant: nil
                )
                metric(
                    title: String(localized: "Max Short-term"),
                    value: viewModel.loudnessResult?.maxShortTermLUFS,
                    unit: "LUFS",
                    compliant: nil
                )
                Spacer()
            }

            if !cachedDisplaySamples.isEmpty {
                chart
            }
        }
        .padding(DesignSystem.Padding.lg)
        .background(DesignSystem.Materials.thin)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .padding(.horizontal, DesignSystem.Padding.lg)
        .onAppear { recomputeDisplaySamples() }
        .onChange(of: viewModel.shortTermLoudness.count) { _, _ in recomputeDisplaySamples() }
    }

    @ViewBuilder
    private func metric(title: String, value: Double?, unit: String, compliant: Bool?) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let compliant {
                    Image(systemName: compliant ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(compliant ? .green : .orange)
                        .help(compliant
                              ? String(localized: "Within EBU R128 limits")
                              : String(localized: "Outside EBU R128 limits"))
                }
            }
        }
    }

    private var chart: some View {
        Chart(cachedDisplaySamples) { sample in
            LineMark(
                x: .value("Time (s)", sample.time),
                y: .value("LUFS", sample.lufs)
            )
            .foregroundStyle(DesignSystem.Colors.Chart.primary)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            RuleMark(y: .value("Target", -23.0))
                .foregroundStyle(.green.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: chartDomain)
        .chartYAxisLabel(String(localized: "Short-term LUFS"))
        .frame(height: 120)
    }

    private var chartDomain: ClosedRange<Double> {
        let values = cachedDisplaySamples.map(\.lufs)
        guard let min = values.min(), let max = values.max() else { return -40...0 }
        return (Swift.min(min, -25) - 3)...(Swift.max(max, -20) + 3)
    }
}
