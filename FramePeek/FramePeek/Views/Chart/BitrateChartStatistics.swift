import Foundation
import FramePeekCore

struct BitrateChartStatistics {
    let samples: [BitrateSample]
    /// Raw frames expected to be pre-sorted by PTS (sorted once at storage time in FramePeekViewModel)
    let rawFrames: [RawFrame]?
    let effectiveFPS: Double?

    init(samples: [BitrateSample], rawFrames: [RawFrame]? = nil, effectiveFPS: Double? = nil) {
        self.samples = samples
        self.rawFrames = rawFrames
        self.effectiveFPS = effectiveFPS
    }

    var maxBitrateKbps: Double {
        // Calculate from rawFrames if available (more accurate, no downsampling)
        if let rawFrames = rawFrames, !rawFrames.isEmpty {
            let estimatedFPS = effectiveFPS ?? 30.0
            let defaultFrameDuration = 1.0 / estimatedFPS
            guard !rawFrames.isEmpty else { return 1 }

            let startTime = rawFrames.first!.pts
            let endTime = rawFrames.last!.pts
            let totalDuration = endTime - startTime + defaultFrameDuration
            let numBuckets = Int(ceil(totalDuration / 1.0))

            guard numBuckets > 0 else { return 1 }

            var bitrates: [Double] = []
            bitrates.reserveCapacity(numBuckets)

            var frameIndex = 0
            for bucketIndex in 0..<numBuckets {
                let bucketStart = startTime + Double(bucketIndex) * 1.0
                let bucketEnd = bucketStart + 1.0

                // Advance to first frame in this bucket
                while frameIndex < rawFrames.count && rawFrames[frameIndex].pts < bucketStart {
                    frameIndex += 1
                }

                // Sum frames in bucket [bucketStart, bucketEnd)
                var totalBytes: Int64 = 0
                var tempIndex = frameIndex
                while tempIndex < rawFrames.count && rawFrames[tempIndex].pts < bucketEnd {
                    totalBytes += rawFrames[tempIndex].size
                    tempIndex += 1
                }

                // Calculate bitrate for this 1-second bucket
                if totalBytes > 0 {
                    let bitrate = (Double(totalBytes) * 8.0) / 1.0
                    bitrates.append(bitrate)
                }
            }

            guard !bitrates.isEmpty else { return 1 }
            let maxBits = bitrates.max() ?? 1
            return Double(maxBits) / 1000.0
        }

        // Fallback to samples
        let maxBits = samples.map(\.bitrate).max() ?? 1
        return Double(maxBits) / 1000.0
    }

    var minBitrateKbps: Double {
        // Calculate from rawFrames if available (more accurate, no downsampling)
        if let rawFrames = rawFrames, !rawFrames.isEmpty {
            let estimatedFPS = effectiveFPS ?? 30.0
            let defaultFrameDuration = 1.0 / estimatedFPS
            let startTime = rawFrames.first!.pts
            let endTime = rawFrames.last!.pts
            let totalDuration = endTime - startTime + defaultFrameDuration
            let numBuckets = Int(ceil(totalDuration / 1.0))

            guard numBuckets > 0 else { return 0 }

            var bitrates: [Double] = []
            bitrates.reserveCapacity(numBuckets)

            var frameIndex = 0
            for bucketIndex in 0..<numBuckets {
                let bucketStart = startTime + Double(bucketIndex) * 1.0
                let bucketEnd = bucketStart + 1.0

                // Advance to first frame in this bucket
                while frameIndex < rawFrames.count && rawFrames[frameIndex].pts < bucketStart {
                    frameIndex += 1
                }

                // Sum frames in bucket [bucketStart, bucketEnd)
                var totalBytes: Int64 = 0
                var tempIndex = frameIndex
                while tempIndex < rawFrames.count && rawFrames[tempIndex].pts < bucketEnd {
                    totalBytes += rawFrames[tempIndex].size
                    tempIndex += 1
                }

                // Calculate bitrate for this 1-second bucket
                if totalBytes > 0 {
                    let bitrate = (Double(totalBytes) * 8.0) / 1.0
                    bitrates.append(bitrate)
                }
            }

            guard !bitrates.isEmpty else { return 0 }
            let minBits = bitrates.min() ?? 0
            return Double(minBits) / 1000.0
        }

        // Fallback to samples
        let minBits = samples.map(\.bitrate).min() ?? 0
        return Double(minBits) / 1000.0
    }

    var avgBitrateKbps: Double {
        guard !samples.isEmpty else { return 0 }

        // Use weighted average if durations are available
        let totalDuration = samples.reduce(0.0) { $0 + $1.duration }
        if totalDuration > 0 {
            // Weighted average: sum(bitrate * duration) / sum(duration)
            let weightedSum = samples.reduce(0.0) { $0 + ($1.bitrate * $1.duration) }
            return (weightedSum / totalDuration) / 1000.0
        } else {
            // Fallback to simple average if no durations
            let sum = samples.reduce(0.0) { $0 + $1.bitrate }
            return (sum / Double(samples.count)) / 1000.0
        }
    }

    var stdDevKbps: Double {
        guard samples.count > 1 else { return 0 }
        let avg = avgBitrateKbps * 1000.0
        let variance = samples.reduce(0.0) { sum, sample in
            let diff = sample.bitrate - avg
            return sum + diff * diff
        } / Double(samples.count)
        return sqrt(variance) / 1000.0
    }

    var maxTime: Double {
        samples.map(\.time).max() ?? 0
    }

    var headerPeakText: String {
        if samples.isEmpty { return "—" }
        return "\(maxBitrateKbps.formatted(.number.precision(.fractionLength(0)))) kb/s"
    }

    var headerDurationText: String {
        if samples.isEmpty { return "—" }
        return "\(maxTime.formatted(.number.precision(.fractionLength(0)))) s"
    }

    var headerAvgText: String {
        if samples.isEmpty { return "—" }
        return "\(avgBitrateKbps.formatted(.number.precision(.fractionLength(0)))) kb/s"
    }

    var headerStdDevText: String {
        if samples.isEmpty { return "—" }
        return "±\(stdDevKbps.formatted(.number.precision(.fractionLength(0))))"
    }

    func niceStep(forMax max: Double, targetTicks: Int) -> Double {
        guard max > 0, targetTicks > 0 else { return 1 }
        let rough = max / Double(targetTicks)
        let magnitude = pow(10.0, floor(log10(rough)))
        let residual = rough / magnitude

        let nice: Double
        if residual < 1.5 { nice = 1 } else if residual < 3 { nice = 2 } else if residual < 7 { nice = 5 } else { nice = 10 }

        return nice * magnitude
    }
}
