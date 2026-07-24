import SwiftUI
import Charts
import FramePeekCore

struct BrightnessChartView: View {
    let samples: [ColorSample]
    var frameRate: Double?

    private let maxDisplayPoints = 500

    // MARK: - Cached Display Samples

    @State private var cachedDisplaySamples: [ColorSample] = []
    @State private var lastDisplaySamplesInputHash: Int = 0

    private func recomputeDisplaySamples() {
        let inputHash = samples.count
        guard inputHash != lastDisplaySamplesInputHash else { return }
        lastDisplaySamplesInputHash = inputHash
        cachedDisplaySamples = downsampleLTTB(samples, targetCount: maxDisplayPoints, x: { $0.time }, y: { $0.brightness })
    }

    private var maxTime: Double {
        samples.last?.time ?? 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Brightness")
                .font(.subheadline)
                .fontWeight(.semibold)

            GeometryReader { geometry in
                let calculatedHeight = max(geometry.size.width * 0.15, 150) // 15% of width, min 150

                Chart {
                    ForEach(cachedDisplaySamples) { sample in
                        LineMark(
                            x: .value("Time (s)", sample.time),
                            y: .value("Brightness", sample.brightness)
                        )
                        .foregroundStyle(.yellow)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.medium))

                        AreaMark(
                            x: .value("Time (s)", sample.time),
                            y: .value("Brightness", sample.brightness)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    .yellow.opacity(0.3),
                                    .yellow.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.linear)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartXScale(domain: (samples.first?.time ?? 0)...(samples.last?.time ?? 1))
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(DesignSystem.Colors.Chart.grid)
                        AxisTick().foregroundStyle(DesignSystem.Colors.Chart.axisTick)
                        AxisValueLabel {
                            if let t = value.as(Double.self) {
                                Text(formatTimeForChart(t, frameRate: frameRate))
                                    .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(DesignSystem.Colors.Chart.gridY)
                        AxisTick().foregroundStyle(DesignSystem.Colors.Chart.axisTick)
                        AxisValueLabel {
                            if let b = value.as(Double.self) {
                                Text("\(b, specifier: "%.2f")")
                                    .foregroundStyle(DesignSystem.Colors.Chart.axisLabel)
                            }
                        }
                    }
                }
                .chartPlotStyle { plot in
                    plot
                        .background(DesignSystem.Colors.Chart.background)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
                }
                .padding(.top, DesignSystem.Padding.sm)
                .padding(.bottom, DesignSystem.Padding.lg)
                .clipped()
                .frame(height: calculatedHeight)
            }
            .frame(height: 150) // Minimum height fallback
        }
        .padding(.bottom, DesignSystem.Padding.md)
        .onAppear { recomputeDisplaySamples() }
        .onChange(of: samples.count) { _, _ in recomputeDisplaySamples() }
    }
}
