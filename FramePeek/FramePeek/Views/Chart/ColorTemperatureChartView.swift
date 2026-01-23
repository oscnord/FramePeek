import SwiftUI
import Charts

struct ColorTemperatureChartView: View {
    let samples: [ColorSample]
    var frameRate: Double?

    private let maxDisplayPoints = 500

    private var validSamples: [ColorSample] {
        samples.filter { $0.colorTemperature != nil }
    }

    private var displaySamples: [ColorSample] {
        downsampleColorSamplesForTemperature(validSamples, targetCount: maxDisplayPoints)
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
                        ForEach(displaySamples) { sample in
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

private func downsampleColorSamplesForTemperature(_ samples: [ColorSample], targetCount: Int) -> [ColorSample] {
    guard samples.count > targetCount, targetCount >= 2 else { return samples }

    var result: [ColorSample] = []
    result.reserveCapacity(targetCount)

    result.append(samples[0])

    let bucketSize = Double(samples.count - 2) / Double(targetCount - 2)
    var lastSelectedIndex = 0

    for i in 0..<(targetCount - 2) {
        let bucketStart = Int(Double(i) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, samples.count - 1)

        let nextBucketStart = bucketEnd
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, samples.count - 1)

        var avgX: Double = 0
        var avgY: Double = 0
        var validCount = 0

        for j in nextBucketStart...nextBucketEnd {
            if let temp = samples[j].colorTemperature {
                avgX += samples[j].time
                avgY += temp
                validCount += 1
            }
        }

        if validCount > 0 {
            avgX /= Double(validCount)
            avgY /= Double(validCount)
        } else {
            avgX = samples[nextBucketStart].time
            avgY = samples[lastSelectedIndex].colorTemperature ?? 5500
        }

        var maxArea: Double = -1
        var maxAreaIndex = bucketStart

        let pointA = samples[lastSelectedIndex]
        let pointATemp = pointA.colorTemperature ?? 5500

        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            if let pointBTemp = pointB.colorTemperature {
                let area = abs(
                    (pointA.time - avgX) * (pointBTemp - pointATemp) -
                    (pointA.time - pointB.time) * (avgY - pointATemp)
                ) * 0.5

                if area > maxArea {
                    maxArea = area
                    maxAreaIndex = j
                }
            }
        }

        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }

    result.append(samples[samples.count - 1])

    return result
}
