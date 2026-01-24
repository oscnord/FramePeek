import Foundation

/// Utility functions for frame pattern synthesis and analysis

/// Synthesizes a typical IBBP frame pattern for a given frame index
/// Pattern: I B B P B B P B B P ...
/// - Parameter frameIndex: 0-based index of the frame in the GOP
/// - Returns: The frame type for that index
func synthesizeIBBPFrameType(at frameIndex: Int) -> FrameType {
    if frameIndex == 0 {
        return .i  // First frame is always I-frame (keyframe)
    } else {
        // Pattern after I-frame: B B P B B P B B P ...
        let posInPattern = (frameIndex - 1) % 3
        return (posInPattern == 2) ? .p : .b
    }
}

/// Generates frame info for a GOP using IBBP pattern
/// - Parameters:
///   - startTime: Start time of the GOP in seconds
///   - frameCount: Number of frames in the GOP
///   - gopDuration: Duration of the GOP in seconds
/// - Returns: Array of FrameInfo with synthesized types
func synthesizeGOPFrames(startTime: Double, frameCount: Int, gopDuration: Double) -> [FrameInfo] {
    guard frameCount > 0, gopDuration > 0 else { return [] }

    let frameDuration = gopDuration / Double(frameCount)
    var frames: [FrameInfo] = []

    for i in 0..<frameCount {
        let frameTime = startTime + Double(i) * frameDuration
        let frameType = synthesizeIBBPFrameType(at: i)
        frames.append(FrameInfo(time: frameTime, type: frameType))
    }

    return frames
}

/// Calculates which GOPs fall within a time window
/// - Parameters:
///   - windowStart: Start of the visible window in seconds
///   - windowEnd: End of the visible window in seconds
///   - gopDuration: Duration of each GOP in seconds
///   - videoDuration: Total video duration in seconds
/// - Returns: Range of GOP indices that overlap with the window
func calculateGOPsInWindow(
    windowStart: Double,
    windowEnd: Double,
    gopDuration: Double,
    videoDuration: Double
) -> ClosedRange<Int>? {
    guard gopDuration > 0, videoDuration > 0 else { return nil }

    let firstGOPIndex = max(0, Int(floor(windowStart / gopDuration)))
    let lastGOPIndex = min(
        Int(ceil(windowEnd / gopDuration)),
        Int(ceil(videoDuration / gopDuration)) - 1
    )

    guard firstGOPIndex <= lastGOPIndex else { return nil }
    return firstGOPIndex...lastGOPIndex
}

/// Extrapolates frame types for a time window based on fixed GOP structure
/// - Parameters:
///   - windowStart: Start of the visible window in seconds
///   - windowEnd: End of the visible window in seconds
///   - gopDuration: Duration of each GOP in seconds
///   - frameCount: Number of frames per GOP
///   - videoDuration: Total video duration in seconds
///   - framePattern: Optional pattern from representative GOP (used if provided)
/// - Returns: Array of FrameInfo for frames within the window
func extrapolateFramesForWindow(
    windowStart: Double,
    windowEnd: Double,
    gopDuration: Double,
    frameCount: Int,
    videoDuration: Double,
    framePattern: [FrameInfo]? = nil
) -> [FrameInfo] {
    guard gopDuration > 0, frameCount > 0, videoDuration > 0 else { return [] }

    var frames: [FrameInfo] = []
    let frameDuration = gopDuration / Double(frameCount)

    guard let gopRange = calculateGOPsInWindow(
        windowStart: windowStart,
        windowEnd: windowEnd,
        gopDuration: gopDuration,
        videoDuration: videoDuration
    ) else { return [] }

    for gopIndex in gopRange {
        let gopStartTime = Double(gopIndex) * gopDuration

        // Don't go past video duration
        if gopStartTime >= videoDuration {
            break
        }

        for frameIndex in 0..<frameCount {
            let frameTime = gopStartTime + Double(frameIndex) * frameDuration

            // Check if frame is within window and video bounds
            if frameTime >= windowStart && frameTime <= windowEnd && frameTime < videoDuration {
                let frameType: FrameType

                if let pattern = framePattern, !pattern.isEmpty {
                    // Use actual pattern from representative GOP
                    let patternIndex = frameIndex % pattern.count
                    frameType = pattern[patternIndex].type
                } else {
                    // Synthesize typical IBBP pattern
                    frameType = synthesizeIBBPFrameType(at: frameIndex)
                }

                frames.append(FrameInfo(time: frameTime, type: frameType))
            }
        }
    }

    return frames.sorted { $0.time < $1.time }
}
