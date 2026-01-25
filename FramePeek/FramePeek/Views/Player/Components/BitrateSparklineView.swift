import SwiftUI
import FramePeekCore

/// A compact sparkline visualization showing bitrate over a rolling time window
struct BitrateSparklineView: View {
    let samples: [BitrateSample]
    let currentTime: Double
    let windowSeconds: Double
    let width: CGFloat
    let height: CGFloat

    init(
        samples: [BitrateSample],
        currentTime: Double,
        windowSeconds: Double = 15,
        width: CGFloat = 80,
        height: CGFloat = 20
    ) {
        self.samples = samples
        self.currentTime = currentTime
        self.windowSeconds = windowSeconds
        self.width = width
        self.height = height
    }

    private var windowSamples: [BitrateSample] {
        let windowStart = max(0, currentTime - windowSeconds)
        let windowEnd = currentTime
        return samples.filter { $0.time >= windowStart && $0.time <= windowEnd }
            .sorted { $0.time < $1.time }
    }

    private var bitrateRange: (min: Double, max: Double) {
        guard !windowSamples.isEmpty else { return (0, 1) }
        let bitrates = windowSamples.map(\.bitrate)
        let minBitrate = bitrates.min() ?? 0
        let maxBitrate = bitrates.max() ?? 1
        // Add 10% padding to range
        let padding = (maxBitrate - minBitrate) * 0.1
        return (max(0, minBitrate - padding), maxBitrate + padding)
    }

    var body: some View {
        Canvas { context, size in
            guard windowSamples.count >= 2 else { return }

            let range = bitrateRange
            let bitrateSpan = range.max - range.min
            guard bitrateSpan > 0 else { return }

            let windowStart = max(0, currentTime - windowSeconds)

            // Build the path
            var path = Path()
            var areaPath = Path()

            for (index, sample) in windowSamples.enumerated() {
                let x = ((sample.time - windowStart) / windowSeconds) * size.width
                let normalizedY = (sample.bitrate - range.min) / bitrateSpan
                let y = size.height - (normalizedY * size.height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                    areaPath.move(to: CGPoint(x: x, y: size.height))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                    areaPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Close area path
            if let lastSample = windowSamples.last {
                let lastX = ((lastSample.time - windowStart) / windowSeconds) * size.width
                areaPath.addLine(to: CGPoint(x: lastX, y: size.height))
                areaPath.closeSubpath()
            }

            // Draw area fill
            let gradient = Gradient(colors: [
                DesignSystem.Colors.Chart.primaryAreaTop.opacity(0.5),
                DesignSystem.Colors.Chart.primaryAreaBottom.opacity(0.2)
            ])
            context.fill(
                areaPath,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Draw line
            context.stroke(
                path,
                with: .color(DesignSystem.Colors.Chart.primary.opacity(0.8)),
                lineWidth: 1.5
            )

            // Draw current position marker
            let markerX = size.width  // Current time is at the right edge
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: markerX, y: 0))
                    p.addLine(to: CGPoint(x: markerX, y: size.height))
                },
                with: .color(Color.primary.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }
}
