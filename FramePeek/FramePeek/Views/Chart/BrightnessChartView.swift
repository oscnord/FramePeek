import SwiftUI
import Charts

struct BrightnessChartView: View {
    let samples: [ColorSample]
    var frameRate: Double? = nil
    
    private let maxDisplayPoints = 500
    
    private var displaySamples: [ColorSample] {
        downsampleColorSamples(samples, targetCount: maxDisplayPoints)
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
                    ForEach(displaySamples) { sample in
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
    }
}

func downsampleColorSamples(_ samples: [ColorSample], targetCount: Int) -> [ColorSample] {
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
        let nextBucketCount = nextBucketEnd - nextBucketStart + 1
        
        for j in nextBucketStart...nextBucketEnd {
            avgX += samples[j].time
            avgY += samples[j].brightness
        }
        avgX /= Double(nextBucketCount)
        avgY /= Double(nextBucketCount)
        
        var maxArea: Double = -1
        var maxAreaIndex = bucketStart
        
        let pointA = samples[lastSelectedIndex]
        
        for j in bucketStart..<bucketEnd {
            let pointB = samples[j]
            let area = abs(
                (pointA.time - avgX) * (pointB.brightness - pointA.brightness) -
                (pointA.time - pointB.time) * (avgY - pointA.brightness)
            ) * 0.5
            
            if area > maxArea {
                maxArea = area
                maxAreaIndex = j
            }
        }
        
        result.append(samples[maxAreaIndex])
        lastSelectedIndex = maxAreaIndex
    }
    
    result.append(samples[samples.count - 1])
    
    return result
}
