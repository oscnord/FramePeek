import SwiftUI

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
        case .i:
            return Color(red: 0.0, green: 0.48, blue: 1.0) // #007AFF
        case .p:
            return Color(red: 1.0, green: 0.58, blue: 0.0) // #FF9500
        case .b:
            return Color(red: 1.0, green: 0.23, blue: 0.19) // #FF3B30
        case .unknown:
            return .gray
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

                // Calculate frame durations
                let segmentDuration = visible.last!.time - visible.first!.time
                let estimatedFrameDuration = visible.count > 1 ? segmentDuration / Double(visible.count - 1) : 0.033

                for (idx, frame) in visible.enumerated() {
                    let nextFrameTime: Double
                    if idx < visible.count - 1 {
                        nextFrameTime = visible[idx + 1].time
                    } else {
                        nextFrameTime = min(frame.time + estimatedFrameDuration, domainEnd)
                    }

                    // Calculate position relative to domainStart
                    // If this is the first frame and it's very close to domainStart, align it to domainStart
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

                    // Fill
                    context.fill(path, with: .color(color.opacity(isHovered ? 0.9 : 0.7)))

                    // Border for I-frames
                    if frame.type == .i {
                        context.stroke(path, with: .color(color), lineWidth: 1.5)
                    } else if isHovered {
                        context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = value.location.x
                        let time = domainStart + (Double(x / width) * domainDuration)

                        if let frameIndex = visibleFrames.firstIndex(where: { abs($0.time - time) < 0.1 }) {
                            hoveredFrameIndex = frameIndex
                        }
                    }
                    .onEnded { value in
                        let x = value.location.x
                        let time = domainStart + (Double(x / width) * domainDuration)

                        if let frame = visibleFrames.first(where: { abs($0.time - time) < 0.1 }) {
                            onFrameClick?(frame)
                        }
                        hoveredFrameIndex = nil
                    }
            )
        }
    }
}
