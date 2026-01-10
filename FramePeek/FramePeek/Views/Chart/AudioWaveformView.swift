import SwiftUI

struct AudioWaveformView: View {
    let trackIndex: Int
    let trackInfo: AudioTrackInfo
    let samples: [WaveformSample]
    let duration: Double
    @ObservedObject var viewModel: FramePeekViewModel
    
    private var displaySamples: [WaveformSample] {
        let filteredSamples: [WaveformSample]
        if let range = viewModel.visibleTimeRange {
            filteredSamples = samples.filter { range.contains($0.time) }
        } else {
            filteredSamples = samples
        }
        return filteredSamples
    }
    
    private var waveformHeight: CGFloat {
        // Fixed compact height for all waveforms
        80
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // Background with subtle grid
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Materials.ultraThin)
                    .overlay(
                        WaveformGrid(rect: geometry.frame(in: .local))
                            .stroke(DesignSystem.Colors.Chart.grid.opacity(0.3), lineWidth: 0.5)
                    )
                
                if displaySamples.isEmpty {
                    // Empty state
                    Text("No waveform data")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                } else {
                    // Waveform path
                    WaveformShape(samples: displaySamples, height: geometry.size.height)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.Chart.primary.opacity(0.8),
                                    DesignSystem.Colors.Chart.primary.opacity(0.4)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .frame(height: waveformHeight)
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
        
        let centerY = rect.midY
        let maxAmplitude = samples.map { max($0.amplitude, $0.maxAmplitude) }.max() ?? 1.0
        let scale = maxAmplitude > 0 ? (rect.height / 2.0) / maxAmplitude : rect.height / 2.0
        
        // Find time range
        let minTime = samples.first?.time ?? 0
        let maxTime = samples.last?.time ?? 1
        let timeRange = max(maxTime - minTime, 0.001)
        
        // Draw waveform as filled area
        // Top half (positive amplitude)
        var topPoints: [CGPoint] = []
        topPoints.reserveCapacity(samples.count)
        
        for sample in samples {
            let x = rect.minX + CGFloat((sample.time - minTime) / timeRange) * rect.width
            let amplitude = sample.maxAmplitude > 0 ? sample.maxAmplitude : sample.amplitude
            let y = centerY - CGFloat(amplitude * scale)
            topPoints.append(CGPoint(x: x, y: y))
        }
        
        // Bottom half (mirrored)
        var bottomPoints: [CGPoint] = []
        bottomPoints.reserveCapacity(samples.count)
        
        for sample in samples.reversed() {
            let x = rect.minX + CGFloat((sample.time - minTime) / timeRange) * rect.width
            let amplitude = sample.minAmplitude > 0 ? sample.minAmplitude : sample.amplitude
            let y = centerY + CGFloat(amplitude * scale)
            bottomPoints.append(CGPoint(x: x, y: y))
        }
        
        // Create closed path
        if let firstTop = topPoints.first {
            path.move(to: firstTop)
            
            // Draw top curve
            for point in topPoints.dropFirst() {
                path.addLine(to: point)
            }
            
            // Draw bottom curve (reversed)
            if let firstBottom = bottomPoints.first {
                path.addLine(to: firstBottom)
                for point in bottomPoints.dropFirst() {
                    path.addLine(to: point)
                }
            }
            
            path.closeSubpath()
        }
        
        return path
    }
}

// MARK: - Waveform Grid

struct WaveformGrid: Shape {
    let rect: CGRect
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let centerY = rect.midY
        
        // Draw center line
        path.move(to: CGPoint(x: rect.minX, y: centerY))
        path.addLine(to: CGPoint(x: rect.maxX, y: centerY))
        
        // Draw a few horizontal reference lines at equal intervals
        let lineCount = 3
        for i in 1..<lineCount {
            let offset = CGFloat(i) / CGFloat(lineCount) * (rect.height / 2.0)
            let yTop = centerY - offset
            let yBottom = centerY + offset
            
            if yTop >= rect.minY {
                path.move(to: CGPoint(x: rect.minX, y: yTop))
                path.addLine(to: CGPoint(x: rect.maxX, y: yTop))
            }
            
            if yBottom <= rect.maxY {
                path.move(to: CGPoint(x: rect.minX, y: yBottom))
                path.addLine(to: CGPoint(x: rect.maxX, y: yBottom))
            }
        }
        
        return path
    }
}

