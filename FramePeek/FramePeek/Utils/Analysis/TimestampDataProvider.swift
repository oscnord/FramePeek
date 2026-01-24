import Foundation

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
    
    /// Finds the GOP segment containing the given timestamp
    static func findGOPAt(time: Double, segments: [GOPSegment]) -> (index: Int, segment: GOPSegment)? {
        for (index, segment) in segments.enumerated() {
            if time >= segment.startTime && time < segment.endTime {
                return (index, segment)
            }
        }
        // If time is exactly at the end of the last segment
        if let lastIndex = segments.indices.last,
           let last = segments.last,
           abs(time - last.endTime) < 0.001 {
            return (lastIndex, last)
        }
        return nil
    }
    
    /// Gets the frame type at a specific time from a list of frames
    static func getFrameTypeAt(time: Double, frames: [FrameInfo]) -> FrameType? {
        // Find the frame closest to this time
        let sortedFrames = frames.sorted { $0.time < $1.time }
        
        // Find frame containing or closest to this time
        var closestFrame: FrameInfo?
        var closestDistance = Double.infinity
        
        for frame in sortedFrames {
            let distance = abs(frame.time - time)
            if distance < closestDistance {
                closestDistance = distance
                closestFrame = frame
            }
        }
        
        return closestFrame?.type
    }
    
    // MARK: - Bitrate Helpers
    
    /// Interpolates bitrate at a given timestamp
    static func interpolateBitrate(at time: Double, samples: [BitrateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        
        let sortedSamples = samples.sorted { $0.time < $1.time }
        
        // Before first sample
        if time <= sortedSamples.first?.time ?? 0 {
            return sortedSamples.first?.bitrate
        }
        
        // After last sample
        if time >= sortedSamples.last?.time ?? 0 {
            return sortedSamples.last?.bitrate
        }
        
        // Find two samples to interpolate between
        for i in 0..<sortedSamples.count - 1 {
            let s1 = sortedSamples[i]
            let s2 = sortedSamples[i + 1]
            
            if time >= s1.time && time <= s2.time {
                let t = (time - s1.time) / (s2.time - s1.time)
                return s1.bitrate + (s2.bitrate - s1.bitrate) * t
            }
        }
        
        return sortedSamples.first?.bitrate
    }
    
    // MARK: - Waveform Helpers
    
    /// Interpolates audio amplitude at a given timestamp
    static func interpolateWaveform(at time: Double, samples: [WaveformSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        
        let sortedSamples = samples.sorted { $0.time < $1.time }
        
        // Before first sample
        if time <= sortedSamples.first?.time ?? 0 {
            return sortedSamples.first?.amplitude
        }
        
        // After last sample
        if time >= sortedSamples.last?.time ?? 0 {
            return sortedSamples.last?.amplitude
        }
        
        // Find two samples to interpolate between
        for i in 0..<sortedSamples.count - 1 {
            let s1 = sortedSamples[i]
            let s2 = sortedSamples[i + 1]
            
            if time >= s1.time && time <= s2.time {
                let t = (time - s1.time) / (s2.time - s1.time)
                return s1.amplitude + (s2.amplitude - s1.amplitude) * t
            }
        }
        
        return sortedSamples.first?.amplitude
    }
    
    // MARK: - Keyframe Helpers
    
    /// Finds the nearest keyframe to the given timestamp
    /// Returns (distance in seconds, isAtKeyframe)
    static func findNearestKeyframe(to time: Double, keyframes: [KeyframeThumbnail], threshold: Double = 0.05) -> (Double, Bool) {
        guard !keyframes.isEmpty else { return (0, false) }
        
        var nearestDistance = Double.infinity
        
        for keyframe in keyframes {
            let distance = abs(keyframe.time - time)
            if distance < nearestDistance {
                nearestDistance = distance
            }
        }
        
        let isAtKeyframe = nearestDistance < threshold
        return (nearestDistance, isAtKeyframe)
    }
    
    // MARK: - Color Helpers
    
    /// Interpolates color data at a given timestamp
    static func interpolateColor(at time: Double, samples: [ColorSample]) -> (brightness: Double, colorTemperature: Double?)? {
        guard !samples.isEmpty else { return nil }
        
        let sortedSamples = samples.sorted { $0.time < $1.time }
        
        // Before first sample
        if time <= sortedSamples.first?.time ?? 0 {
            if let first = sortedSamples.first {
                return (first.brightness, first.colorTemperature)
            }
            return nil
        }
        
        // After last sample
        if time >= sortedSamples.last?.time ?? 0 {
            if let last = sortedSamples.last {
                return (last.brightness, last.colorTemperature)
            }
            return nil
        }
        
        // Find two samples to interpolate between
        for i in 0..<sortedSamples.count - 1 {
            let s1 = sortedSamples[i]
            let s2 = sortedSamples[i + 1]
            
            if time >= s1.time && time <= s2.time {
                let t = (time - s1.time) / (s2.time - s1.time)
                let brightness = s1.brightness + (s2.brightness - s1.brightness) * t
                
                var colorTemp: Double?
                if let t1 = s1.colorTemperature, let t2 = s2.colorTemperature {
                    colorTemp = t1 + (t2 - t1) * t
                } else {
                    colorTemp = s1.colorTemperature ?? s2.colorTemperature
                }
                
                return (brightness, colorTemp)
            }
        }
        
        return nil
    }
}
