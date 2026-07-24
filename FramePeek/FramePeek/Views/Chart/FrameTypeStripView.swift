import SwiftUI
import FramePeekCore

struct FrameTypeStripView: View {
    let frames: [FrameInfo]
    let domainStart: Double
    let domainEnd: Double
    let onFrameClick: ((FrameInfo) -> Void)?

    @State private var hoveredFrameIndex: Int?

    private var visibleFrames: [FrameInfo] {
        frames.filter { frame in
            frame.time >= domainStart && frame.time <= domainEnd
        }
    }

    private func frameColor(for type: FrameType) -> Color {
        switch type {
        case .i: return DesignSystem.Colors.FrameType.i
        case .p: return DesignSystem.Colors.FrameType.p
        case .b: return DesignSystem.Colors.FrameType.b
        case .unknown: return DesignSystem.Colors.FrameType.unknown
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let domainDuration = max(0.001, domainEnd - domainStart)

            Canvas { context, _ in
                let visible = visibleFrames.sorted { $0.time < $1.time }
                guard !visible.isEmpty else { return }

                let maxBuckets = max(1, Int(width))
                if visible.count > maxBuckets {
                    // Downsample: bucket frames into pixel-width bins
                    drawDownsampledFrames(
                        context: context, frames: visible,
                        width: width, height: height,
                        domainStart: domainStart, domainDuration: domainDuration,
                        bucketCount: maxBuckets
                    )
                } else {
                    // Render individual frames
                    drawIndividualFrames(
                        context: context, frames: visible,
                        width: width, height: height,
                        domainStart: domainStart, domainDuration: domainDuration
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = value.location.x
                        let time = domainStart + (Double(x / width) * domainDuration)
                        let visible = visibleFrames
                        // Binary search for nearest frame
                        hoveredFrameIndex = nearestFrameIndex(to: time, in: visible)
                    }
                    .onEnded { value in
                        let x = value.location.x
                        let time = domainStart + (Double(x / width) * domainDuration)

                        if let idx = nearestFrameIndex(to: time, in: visibleFrames),
                           abs(visibleFrames[idx].time - time) < 0.1 {
                            onFrameClick?(visibleFrames[idx])
                        }
                        hoveredFrameIndex = nil
                    }
            )
        }
    }

    // MARK: - Individual Frame Drawing

    private func drawIndividualFrames(
        context: GraphicsContext, frames: [FrameInfo],
        width: CGFloat, height: CGFloat,
        domainStart: Double, domainDuration: Double
    ) {
        guard let firstFrame = frames.first, let lastFrame = frames.last else { return }
        let segmentDuration = lastFrame.time - firstFrame.time
        let estimatedFrameDuration = frames.count > 1 ? segmentDuration / Double(frames.count - 1) : 0.033

        for (idx, frame) in frames.enumerated() {
            let nextFrameTime: Double
            if idx < frames.count - 1 {
                nextFrameTime = frames[idx + 1].time
            } else {
                nextFrameTime = min(frame.time + estimatedFrameDuration, domainEnd)
            }

            let frameStartTime: Double
            if idx == 0 && abs(frame.time - domainStart) < 0.001 {
                frameStartTime = domainStart
            } else {
                frameStartTime = frame.time
            }

            let frameStartRatio = max(0, (frameStartTime - domainStart) / domainDuration)
            let frameEndRatio = min(1, (nextFrameTime - domainStart) / domainDuration)

            let frameStartX = CGFloat(frameStartRatio) * width
            let frameEndX = CGFloat(frameEndRatio) * width
            let frameWidth = max(1.0, frameEndX - frameStartX)

            let color = frameColor(for: frame.type)
            let isHovered = hoveredFrameIndex == idx

            let rect = CGRect(
                x: frameStartX,
                y: 0,
                width: frameWidth,
                height: height
            )
            let path = Path(roundedRect: rect, cornerRadius: 2)

            context.fill(path, with: .color(color.opacity(isHovered ? 0.9 : 0.7)))

            if frame.type == .i {
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            } else if isHovered {
                context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1)
            }
        }
    }

    // MARK: - Downsampled Frame Drawing

    private func drawDownsampledFrames(
        context: GraphicsContext, frames: [FrameInfo],
        width: CGFloat, height: CGFloat,
        domainStart: Double, domainDuration: Double,
        bucketCount: Int
    ) {
        let bucketDuration = domainDuration / Double(bucketCount)
        let bucketWidth = max(1.0, width / CGFloat(bucketCount))

        // Single-pass bucketing: walk sorted frames and buckets together
        var frameIdx = 0
        for bucket in 0..<bucketCount {
            let bucketStart = domainStart + Double(bucket) * bucketDuration
            let bucketEnd = bucketStart + bucketDuration

            var iCount = 0, pCount = 0, bCount = 0, unknownCount = 0

            while frameIdx < frames.count && frames[frameIdx].time < bucketEnd {
                if frames[frameIdx].time >= bucketStart {
                    switch frames[frameIdx].type {
                    case .i: iCount += 1
                    case .p: pCount += 1
                    case .b: bCount += 1
                    case .unknown: unknownCount += 1
                    }
                }
                frameIdx += 1
            }

            let totalInBucket = iCount + pCount + bCount + unknownCount
            guard totalInBucket > 0 else { continue }

            let x = CGFloat(bucket) * bucketWidth

            // Draw stacked proportional bar to preserve all frame type visibility
            var currentY: CGFloat = 0
            let total = CGFloat(totalInBucket)

            if iCount > 0 {
                let h = height * CGFloat(iCount) / total
                context.fill(Path(CGRect(x: x, y: currentY, width: bucketWidth, height: h)), with: .color(frameColor(for: .i).opacity(0.75)))
                currentY += h
            }
            if pCount > 0 {
                let h = height * CGFloat(pCount) / total
                context.fill(Path(CGRect(x: x, y: currentY, width: bucketWidth, height: h)), with: .color(frameColor(for: .p).opacity(0.7)))
                currentY += h
            }
            if bCount > 0 {
                let h = height * CGFloat(bCount) / total
                context.fill(Path(CGRect(x: x, y: currentY, width: bucketWidth, height: h)), with: .color(frameColor(for: .b).opacity(0.7)))
                currentY += h
            }
            if unknownCount > 0 {
                let h = height * CGFloat(unknownCount) / total
                context.fill(Path(CGRect(x: x, y: currentY, width: bucketWidth, height: h)), with: .color(frameColor(for: .unknown).opacity(0.5)))
            }

            // Always mark I-frame boundaries with an accent line
            if iCount > 0 {
                var iPath = Path()
                iPath.move(to: CGPoint(x: x, y: 0))
                iPath.addLine(to: CGPoint(x: x, y: height))
                context.stroke(iPath, with: .color(frameColor(for: .i)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Binary Search

    private func nearestFrameIndex(to time: Double, in frames: [FrameInfo]) -> Int? {
        guard !frames.isEmpty else { return nil }

        var lo = 0
        var hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].time < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        if lo == 0 { return 0 }
        if lo >= frames.count { return frames.count - 1 }

        let before = frames[lo - 1]
        let after = frames[lo]
        return abs(before.time - time) <= abs(after.time - time) ? lo - 1 : lo
    }
}
