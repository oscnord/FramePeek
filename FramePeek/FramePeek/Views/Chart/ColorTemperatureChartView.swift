import SwiftUI
import Charts
import FramePeekCore

struct ColorTemperatureChartView: View {
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
        cachedDisplaySamples = downsampleLTTB(validSamples, targetCount: maxDisplayPoints, x: { $0.time }, y: { $0.colorTemperature ?? 0 })
    }

    private var validSamples: [ColorSample] {
        samples.filter { $0.colorTemperature != nil }
    }

    private var maxTime: Double {
        samples.last?.time ?? 1.0
    }

    private var minTemp: Double {
        validSamples.compactMap { $0.colorTemperature }.min() ?? 3000
    }

    private var maxTemp: Double {
        validSamples.compactMap { $0.colorTemperature }.max() ?? 8000
    }

    private var tempRange: ClosedRange<Double> {
        let padding = (maxTemp - minTemp) * 0.1
        let clampedMin = max(2500, minTemp - padding)
        let clampedMax = min(10000, maxTemp + padding)
        return clampedMin...clampedMax
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Color Temperature")
                .font(.subheadline)
                .fontWeight(.semibold)

            if validSamples.isEmpty {
                Text("No color temperature data available")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150) // Minimum height fallback
            } else {
                GeometryReader { geometry in
                    let calculatedHeight = max(geometry.size.width * 0.15, 150) // 15% of width, min 150

                    Chart {
                        ForEach(cachedDisplaySamples) { sample in
                            if let temp = sample.colorTemperature {
                                LineMark(
                                    x: .value("Time (s)", sample.time),
                                    y: .value("Temperature (K)", temp)
                                )
                                .foregroundStyle(DesignSystem.Colors.Chart.primary)
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: DesignSystem.Borders.medium))

                                AreaMark(
                                    x: .value("Time (s)", sample.time),
                                    y: .value("Temperature (K)", temp)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            DesignSystem.Colors.Chart.primary.opacity(0.3),
                                            DesignSystem.Colors.Chart.primary.opacity(0.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.linear)
                            }
                        }
                    }
                    .chartYScale(domain: tempRange)
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
                                if let t = value.as(Double.self) {
                                    Text("\(Int(t))K")
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
        }
        .padding(.top, DesignSystem.Padding.md)
        .onAppear { recomputeDisplaySamples() }
        .onChange(of: samples.count) { _, _ in recomputeDisplaySamples() }
    }

    private func temperatureColor(_ temp: Double) -> Color {
        if temp < 4000 {
            return .orange
        } else if temp < 5500 {
            return .yellow
        } else if temp < 7000 {
            return .cyan
        } else {
            return .blue
        }
    }
}
