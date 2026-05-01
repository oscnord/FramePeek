import SwiftUI
import FramePeekCore

struct AudioWaveformView: View {
    let trackIndex: Int
    let trackInfo: AudioTrackInfo
    let samples: [WaveformSample]
    let duration: Double
    var viewModel: FramePeekViewModel

    // MARK: - Cached Display Samples

    @State private var cachedDisplaySamples: [WaveformSample] = []
    @State private var lastDisplaySamplesInputHash: Int = 0

    /// Maximum points to render for performance (LTTB downsampling)
    private let maxDisplayPoints = 1_000

    private func recomputeDisplaySamples() {
        let inputHash = combineHashValues(samples.count, viewModel.visibleTimeRange?.hashValue ?? 0)
        guard inputHash != lastDisplaySamplesInputHash else { return }
        lastDisplaySamplesInputHash = inputHash

        let filtered: [WaveformSample]
        if let range = viewModel.visibleTimeRange {
            filtered = samples.filter { range.contains($0.time) }
        } else {
            filtered = samples
        }
        cachedDisplaySamples = downsampleWaveformLTTB(filtered, targetCount: maxDisplayPoints)
    }

    private func combineHashValues(_ a: Int, _ b: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(a)
        hasher.combine(b)
        return hasher.finalize()
    }
    
    /// Time domain for the current view
    private var timeDomain: (start: Double, end: Double) {
        if let range = viewModel.visibleTimeRange {
            return (range.lowerBound, range.upperBound)
        }
        let minTime = samples.first?.time ?? 0
        let maxTime = samples.last?.time ?? duration
        return (minTime, maxTime)
    }

    var body: some View {
        GeometryReader { geometry in
            let calculatedHeight = max(geometry.size.width * 0.08, 80) // 8% of width, min 80

            ZStack(alignment: .center) {
                // Background with subtle grid
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Materials.ultraThin)
                    .overlay(
                        WaveformGrid(rect: geometry.frame(in: .local))
                            .stroke(DesignSystem.Colors.Chart.grid.opacity(0.3), lineWidth: 0.5)
                    )

                if cachedDisplaySamples.isEmpty {
                    // Empty state
                    Text("No waveform data")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                } else {
                    // Waveform path - gradient from bottom (darker) to top (lighter)
                    WaveformShape(samples: cachedDisplaySamples, height: calculatedHeight)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.Chart.primary.opacity(0.9),
                                    DesignSystem.Colors.Chart.primary.opacity(0.5)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                }
                
                // Cross-chart sync indicator line
                if let syncTime = viewModel.hoveredTimestamp {
                    crossChartSyncIndicator(time: syncTime, width: geometry.size.width, height: calculatedHeight)
                }
            }
            .frame(height: calculatedHeight)
        }
        .frame(height: 80) // Minimum height fallback
        .onAppear { recomputeDisplaySamples() }
        .onChange(of: samples.count) { _, _ in recomputeDisplaySamples() }
        .onChange(of: viewModel.visibleTimeRange) { _, _ in recomputeDisplaySamples() }
    }
    
    // MARK: - Cross-Chart Sync Indicator
    
    @ViewBuilder
    private func crossChartSyncIndicator(time: Double, width: CGFloat, height: CGFloat) -> some View {
        let domain = timeDomain
        let domainDuration = max(0.001, domain.end - domain.start)
        
        // Only show if time is within visible range
        if time >= domain.start && time <= domain.end {
            let ratio = (time - domain.start) / domainDuration
            let x = CGFloat(ratio) * width
            
            Rectangle()
                .fill(DesignSystem.Colors.Chart.hoveredLine)
                .frame(width: 2, height: height)
                .position(x: x, y: height / 2)
                .allowsHitTesting(false)
        }
    }
}

struct WaveformShape: Shape {
    let samples: [WaveformSample]
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !samples.isEmpty, rect.width > 0, rect.height > 0 else {
            return path
        }

        // Get all amplitude values for scaling
        let amplitudes = samples.map { max($0.amplitude, $0.maxAmplitude) }
        guard let maxAmp = amplitudes.max(), maxAmp > 0 else {
            return path
        }
        
        // Use a small padding from edges
        let padding: CGFloat = 4
        let drawHeight = rect.height - (padding * 2)
        
        // Scale factor: map amplitude (0-1) to available height
        // Waveform goes from bottom (0) to top (max amplitude)
        let scale = drawHeight / maxAmp

        // Find time range
        let minTime = samples.first?.time ?? 0
        let maxTime = samples.last?.time ?? 1
        let timeRange = max(maxTime - minTime, 0.001)

        // Start at bottom-left
        let baselineY = rect.maxY - padding
        path.move(to: CGPoint(x: rect.minX, y: baselineY))

        // Draw line along bottom to first sample
        let firstX = rect.minX + CGFloat((samples[0].time - minTime) / timeRange) * rect.width
        path.addLine(to: CGPoint(x: firstX, y: baselineY))

        // Draw waveform as filled area from baseline
        for sample in samples {
            let x = rect.minX + CGFloat((sample.time - minTime) / timeRange) * rect.width
            let amplitude = max(sample.amplitude, sample.maxAmplitude)
            let scaledHeight = CGFloat(amplitude * scale)
            let y = baselineY - scaledHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close path back to baseline (samples is guaranteed non-empty by guard above)
        let lastX = rect.minX + CGFloat(((samples.last?.time ?? maxTime) - minTime) / timeRange) * rect.width
        path.addLine(to: CGPoint(x: lastX, y: baselineY))
        path.addLine(to: CGPoint(x: rect.minX, y: baselineY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Waveform Grid

struct WaveformGrid: Shape {
    let rect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let padding: CGFloat = 4
        let baselineY = rect.maxY - padding

        // Draw baseline
        path.move(to: CGPoint(x: rect.minX, y: baselineY))
        path.addLine(to: CGPoint(x: rect.maxX, y: baselineY))

        // Draw horizontal reference lines at 25%, 50%, 75%
        let drawHeight = rect.height - (padding * 2)
        for level in [0.25, 0.5, 0.75] {
            let y = baselineY - (drawHeight * CGFloat(level))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        return path
    }
}
