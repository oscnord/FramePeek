import SwiftUI

/// A compact timeline visualization showing frame types (I/P/B) over a rolling time window
struct FrameTypeTimelineView: View {
    let segments: [GOPSegment]
    let currentTime: Double
    let windowSeconds: Double
    let width: CGFloat
    let height: CGFloat
    let representativeGOP: GOPSegment?
    let structureType: GOPStructureType
    let videoDuration: Double?

    init(
        segments: [GOPSegment],
        currentTime: Double,
        windowSeconds: Double = 10,
        width: CGFloat = 80,
        height: CGFloat = 16,
        representativeGOP: GOPSegment? = nil,
        structureType: GOPStructureType = .unknown,
        videoDuration: Double? = nil
    ) {
        self.segments = segments
        self.currentTime = currentTime
        self.windowSeconds = windowSeconds
        self.width = width
        self.height = height
        self.representativeGOP = representativeGOP
        self.structureType = structureType
        self.videoDuration = videoDuration
    }

    /// Whether we can extrapolate frames for the entire video (fixed GOP structure detected)
    private var canExtrapolateFullVideo: Bool {
        // We can extrapolate if we have:
        // 1. A fixed GOP structure (with known frame count)
        // 2. Video duration
        // 3. Either a representative GOP (for duration) or segments to estimate GOP duration
        guard structureType.isFixed,
              let _ = structureType.fixedFrameCount,
              let duration = videoDuration, duration > 0 else {
            return false
        }

        // Need GOP duration - from representative GOP or first segment
        return representativeGOP != nil || !segments.isEmpty
    }

    /// Get the GOP duration for extrapolation
    private var gopDurationForExtrapolation: Double? {
        if let repGOP = representativeGOP, repGOP.duration > 0 {
            return repGOP.duration
        }
        // Fall back to average duration from analyzed segments
        let validDurations = segments.map(\.duration).filter { $0 > 0 }
        guard !validDurations.isEmpty else { return nil }
        return validDurations.reduce(0, +) / Double(validDurations.count)
    }

    /// Get all frames within the visible time window
    private var windowFrames: [FrameInfo] {
        let windowStart = max(0, currentTime - windowSeconds)
        let windowEnd = currentTime

        // If we have a fixed GOP structure, extrapolate across entire video
        if canExtrapolateFullVideo {
            return extrapolateFramesForWindow(windowStart: windowStart, windowEnd: windowEnd)
        }

        // Otherwise, use analyzed segments only
        var frames: [FrameInfo] = []

        for segment in segments {
            // Skip segments entirely outside window
            if segment.endTime < windowStart || segment.startTime > windowEnd {
                continue
            }

            if let segmentFrames = segment.frames, !segmentFrames.isEmpty {
                // Add individual frames within window
                for frame in segmentFrames {
                    if frame.time >= windowStart && frame.time <= windowEnd {
                        frames.append(frame)
                    }
                }
            } else {
                // No frame data - synthesize frames based on frame count or representative GOP
                let synthesizedFrames = synthesizeFrames(for: segment, windowStart: windowStart, windowEnd: windowEnd)
                frames.append(contentsOf: synthesizedFrames)
            }
        }

        return frames.sorted { $0.time < $1.time }
    }

    /// Extrapolate frame types across the entire video based on fixed GOP structure
    private func extrapolateFramesForWindow(windowStart: Double, windowEnd: Double) -> [FrameInfo] {
        guard let duration = videoDuration, duration > 0,
              let gopDuration = gopDurationForExtrapolation, gopDuration > 0,
              let frameCount = structureType.fixedFrameCount, frameCount > 0 else {
            return []
        }

        var frames: [FrameInfo] = []

        // Get frame pattern from representative GOP if available
        let framePattern = representativeGOP?.frames

        let frameDuration = gopDuration / Double(frameCount)

        // Calculate which GOPs fall within our window
        let firstGOPIndex = max(0, Int(floor(windowStart / gopDuration)))
        let lastGOPIndex = Int(ceil(windowEnd / gopDuration))

        // Generate frames for each GOP in the window
        for gopIndex in firstGOPIndex...lastGOPIndex {
            let gopStartTime = Double(gopIndex) * gopDuration

            // Don't go past video duration
            if gopStartTime >= duration {
                break
            }

            for frameIndex in 0..<frameCount {
                let frameTime = gopStartTime + Double(frameIndex) * frameDuration

                // Check if frame is within window and video bounds
                if frameTime >= windowStart && frameTime <= windowEnd && frameTime < duration {
                    let frameType: FrameType

                    if let pattern = framePattern, !pattern.isEmpty {
                        // Use actual pattern from representative GOP
                        let patternIndex = frameIndex % pattern.count
                        frameType = pattern[patternIndex].type
                    } else {
                        // Synthesize typical IBBP pattern
                        if frameIndex == 0 {
                            frameType = .i
                        } else {
                            // Pattern: I B B P B B P B B P ...
                            let posInPattern = (frameIndex - 1) % 3
                            frameType = (posInPattern == 2) ? .p : .b
                        }
                    }

                    frames.append(FrameInfo(time: frameTime, type: frameType))
                }
            }
        }

        return frames.sorted { $0.time < $1.time }
    }

    /// Synthesize frame types for a GOP segment without detailed frame data
    private func synthesizeFrames(for segment: GOPSegment, windowStart: Double, windowEnd: Double) -> [FrameInfo] {
        var frames: [FrameInfo] = []

        // For fixed GOP structure with representative pattern, we can confidently synthesize
        // This works even during preview/partial analysis
        if let repFrames = representativeGOP?.frames, !repFrames.isEmpty {
            // Use fixed frame count from structure type if available, otherwise from segment or representative
            let frameCount: Int
            if let fixedCount = structureType.fixedFrameCount {
                frameCount = fixedCount
            } else {
                frameCount = segment.frameCount ?? repFrames.count
            }

            guard frameCount > 0 else { return frames }
            let frameDuration = segment.duration / Double(frameCount)

            for i in 0..<frameCount {
                let frameTime = segment.startTime + Double(i) * frameDuration
                if frameTime >= windowStart && frameTime <= windowEnd {
                    // Use pattern from representative GOP (cycling if needed)
                    let patternIndex = i % repFrames.count
                    let frameType = repFrames[patternIndex].type
                    frames.append(FrameInfo(time: frameTime, type: frameType))
                }
            }
        } else if let frameCount = segment.frameCount, frameCount > 0 {
            // No representative GOP - synthesize typical IBBP pattern
            let frameDuration = segment.duration / Double(frameCount)

            for i in 0..<frameCount {
                let frameTime = segment.startTime + Double(i) * frameDuration
                if frameTime >= windowStart && frameTime <= windowEnd {
                    let frameType: FrameType
                    if i == 0 {
                        frameType = .i  // First frame is always I
                    } else {
                        // Typical pattern: I B B P B B P B B P ...
                        let posInPattern = (i - 1) % 3
                        frameType = (posInPattern == 2) ? .p : .b
                    }
                    frames.append(FrameInfo(time: frameTime, type: frameType))
                }
            }
        } else if structureType.isFixed, let fixedCount = structureType.fixedFrameCount, fixedCount > 0 {
            // Fixed structure detected but no representative - use fixed count with IBBP pattern
            let frameDuration = segment.duration / Double(fixedCount)

            for i in 0..<fixedCount {
                let frameTime = segment.startTime + Double(i) * frameDuration
                if frameTime >= windowStart && frameTime <= windowEnd {
                    let frameType: FrameType
                    if i == 0 {
                        frameType = .i
                    } else {
                        let posInPattern = (i - 1) % 3
                        frameType = (posInPattern == 2) ? .p : .b
                    }
                    frames.append(FrameInfo(time: frameTime, type: frameType))
                }
            }
        } else {
            // Fallback: just show I-frame at GOP start
            if segment.startTime >= windowStart && segment.startTime <= windowEnd {
                frames.append(FrameInfo(time: segment.startTime, type: .i))
            }
        }

        return frames
    }

    var body: some View {
        Canvas { context, size in
            let windowStart = max(0, currentTime - windowSeconds)
            let frames = windowFrames

            guard !frames.isEmpty else { return }

            // Draw each frame as a vertical bar
            let barWidth: CGFloat = 3

            for frame in frames {
                let x = ((frame.time - windowStart) / windowSeconds) * size.width

                // Height based on frame type (I-frames taller)
                let barHeight: CGFloat
                switch frame.type {
                case .i:
                    barHeight = size.height
                case .p:
                    barHeight = size.height * 0.65
                case .b:
                    barHeight = size.height * 0.4
                case .unknown:
                    barHeight = size.height * 0.3
                }

                let rect = CGRect(
                    x: x - barWidth / 2,
                    y: size.height - barHeight,
                    width: barWidth,
                    height: barHeight
                )

                // Color based on frame type
                let color: Color
                switch frame.type {
                case .i:
                    color = .blue
                case .p:
                    color = .green
                case .b:
                    color = .orange
                case .unknown:
                    color = .gray
                }

                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(color.opacity(0.8))
                )
            }

            // Draw current position marker
            let markerX = size.width
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

/// Legend for frame type colors
struct FrameTypeLegend: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            legendItem(type: .i, label: "I")
            legendItem(type: .p, label: "P")
            legendItem(type: .b, label: "B")
        }
    }

    private func legendItem(type: FrameType, label: String) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(colorFor(type))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func colorFor(_ type: FrameType) -> Color {
        switch type {
        case .i: return .blue
        case .p: return .green
        case .b: return .orange
        case .unknown: return .gray
        }
    }
}
