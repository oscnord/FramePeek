import Foundation
import FramePeekCore

/// Provides aggregated data at a specific timestamp from all available analyses
@MainActor
enum TimestampDataProvider {
    
    /// Collects all available data at the given timestamp from the ViewModel
    static func getData(at time: Double, from viewModel: FramePeekViewModel) -> UnifiedTooltipData {
        var data = UnifiedTooltipData(timestamp: time)
        
        // Bitrate
        if !viewModel.samples.isEmpty {
            if let bitrate = interpolateBitrate(at: time, samples: viewModel.samples) {
                data.bitrate = bitrate
                let maxBitrate = viewModel.samples.map(\.bitrate).max() ?? 1
                data.bitratePercent = maxBitrate > 0 ? bitrate / maxBitrate : 0
            }
        }
        
        // GOP
        if let analysis = viewModel.gopAnalysis,
           let (index, segment) = findGOPAt(time: time, segments: analysis.segments) {
            data.gopIndex = index
            data.gopFrameCount = segment.frameCount
            data.gopDuration = segment.duration
            
            // Frame type - only if cached
            if let cachedFrames = viewModel.gopFrameDetailsCache[segment.id] {
                data.frameType = getFrameTypeAt(time: time, frames: cachedFrames)
            } else if let frames = segment.frames, !frames.isEmpty {
                data.frameType = getFrameTypeAt(time: time, frames: frames)
            }
        }
        
        // Audio (primary track only - index 0)
        if let primaryWaveform = viewModel.waveformData[0], !primaryWaveform.isEmpty {
            data.audioAmplitude = interpolateWaveform(at: time, samples: primaryWaveform)
        }
        
        // Keyframe
        if !viewModel.keyframeThumbs.isEmpty {
            let (distance, isAt) = findNearestKeyframe(to: time, keyframes: viewModel.keyframeThumbs)
            data.nearestKeyframeDistance = distance
            data.isAtKeyframe = isAt
        }
        
        // Color
        if !viewModel.colorSamples.isEmpty {
            if let colorData = interpolateColor(at: time, samples: viewModel.colorSamples) {
                data.brightness = colorData.brightness
                data.colorTemperature = colorData.colorTemperature
            }
        }
        
        return data
    }
    
    // MARK: - GOP Helpers
    
    /// Finds the GOP segment containing the given timestamp using binary search
    static func findGOPAt(time: Double, segments: [GOPSegment]) -> (index: Int, segment: GOPSegment)? {
        guard !segments.isEmpty else { return nil }

        // Binary search: find first segment whose startTime >= time
        let idx = lowerBound(in: segments, targetTime: time, timeKeyPath: \.startTime)

        // Check the segment at idx (if startTime == time, it contains our time)
        if idx < segments.count {
            let seg = segments[idx]
            if time >= seg.startTime && time < seg.endTime {
                return (idx, seg)
            }
        }

        // Check the previous segment (time might fall within it)
        if idx > 0 {
            let seg = segments[idx - 1]
            if time >= seg.startTime && time < seg.endTime {
                return (idx - 1, seg)
            }
        }

        // Edge case: time is exactly at the end of the last segment
        if let lastIndex = segments.indices.last,
           let last = segments.last,
           abs(time - last.endTime) < 0.001 {
            return (lastIndex, last)
        }

        return nil
    }
    
    /// Gets the frame type at a specific time from a list of frames using binary search
    static func getFrameTypeAt(time: Double, frames: [FrameInfo]) -> FrameType? {
        guard let idx = binarySearchClosest(in: frames, targetTime: time, timeKeyPath: \.time) else {
            return nil
        }
        return frames[idx].type
    }
    
    // MARK: - Bitrate Helpers
    
    /// Interpolates bitrate at a given timestamp using binary search
    static func interpolateBitrate(at time: Double, samples: [BitrateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        // Edge cases: before first or after last
        if time <= samples.first!.time { return samples.first!.bitrate }
        if time >= samples.last!.time { return samples.last!.bitrate }

        // Binary search for interpolation pair
        if let (s1, s2, t) = binarySearchInterpolationPair(in: samples, targetTime: time, timeKeyPath: \.time) {
            return s1.bitrate + (s2.bitrate - s1.bitrate) * t
        }

        return samples.first?.bitrate
    }
    
    // MARK: - Waveform Helpers
    
    /// Interpolates audio amplitude at a given timestamp using binary search
    static func interpolateWaveform(at time: Double, samples: [WaveformSample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        // Edge cases: before first or after last
        if time <= samples.first!.time { return samples.first!.amplitude }
        if time >= samples.last!.time { return samples.last!.amplitude }

        // Binary search for interpolation pair
        if let (s1, s2, t) = binarySearchInterpolationPair(in: samples, targetTime: time, timeKeyPath: \.time) {
            return s1.amplitude + (s2.amplitude - s1.amplitude) * t
        }

        return samples.first?.amplitude
    }
    
    // MARK: - Keyframe Helpers
    
    /// Finds the nearest keyframe to the given timestamp using binary search
    /// Returns (distance in seconds, isAtKeyframe)
    static func findNearestKeyframe(to time: Double, keyframes: [KeyframeThumbnail], threshold: Double = 0.05) -> (Double, Bool) {
        guard !keyframes.isEmpty else { return (0, false) }

        guard let idx = binarySearchClosest(in: keyframes, targetTime: time, timeKeyPath: \.time) else {
            return (0, false)
        }

        let nearestDistance = abs(keyframes[idx].time - time)
        let isAtKeyframe = nearestDistance < threshold
        return (nearestDistance, isAtKeyframe)
    }
    
    // MARK: - Color Helpers
    
    /// Interpolates color data at a given timestamp using binary search
    static func interpolateColor(at time: Double, samples: [ColorSample]) -> (brightness: Double, colorTemperature: Double?)? {
        guard !samples.isEmpty else { return nil }

        // Edge cases: before first or after last
        if time <= samples.first!.time {
            return (samples.first!.brightness, samples.first!.colorTemperature)
        }
        if time >= samples.last!.time {
            return (samples.last!.brightness, samples.last!.colorTemperature)
        }

        // Binary search for interpolation pair
        if let (s1, s2, t) = binarySearchInterpolationPair(in: samples, targetTime: time, timeKeyPath: \.time) {
            let brightness = s1.brightness + (s2.brightness - s1.brightness) * t

            var colorTemp: Double?
            if let t1 = s1.colorTemperature, let t2 = s2.colorTemperature {
                colorTemp = t1 + (t2 - t1) * t
            } else {
                colorTemp = s1.colorTemperature ?? s2.colorTemperature
            }

            return (brightness, colorTemp)
        }

        return nil
    }
}
