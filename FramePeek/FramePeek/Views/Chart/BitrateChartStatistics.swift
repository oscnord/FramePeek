import Foundation
import FramePeekCore

struct BitrateChartStatistics {
    let samples: [BitrateSample]
    /// Raw frames expected to be pre-sorted by PTS (sorted once at storage time in FramePeekViewModel)
    let rawFrames: [RawFrame]?
    let effectiveFPS: Double?

    let maxBitrateKbps: Double
    let avgBitrateKbps: Double
    let stdDevKbps: Double

    init(samples: [BitrateSample], rawFrames: [RawFrame]? = nil, effectiveFPS: Double? = nil) {
        self.samples = samples
        self.rawFrames = rawFrames
        self.effectiveFPS = effectiveFPS

        let computedMax: Double
        if let rawFrames, let firstFrame = rawFrames.first, let lastFrame = rawFrames.last {
            let estimatedFPS = effectiveFPS ?? 30.0
            let defaultFrameDuration = 1.0 / estimatedFPS

            let startTime = firstFrame.pts
            let endTime = lastFrame.pts
            let totalDuration = endTime - startTime + defaultFrameDuration
            let numBuckets = Int(ceil(totalDuration / 1.0))

            if numBuckets > 0 {
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

                if bitrates.isEmpty {
                    computedMax = 1
                } else {
                    let maxBits = bitrates.max() ?? 1
                    computedMax = Double(maxBits) / 1000.0
                }
            } else {
                computedMax = 1
            }
        } else {
            // Fallback to samples
            let maxBits = samples.map(\.bitrate).max() ?? 1
            computedMax = Double(maxBits) / 1000.0
        }
        self.maxBitrateKbps = computedMax

        let computedAvg: Double
        if samples.isEmpty {
            computedAvg = 0
        } else {
            // Use weighted average if durations are available
            let totalDuration = samples.reduce(0.0) { $0 + $1.duration }
            if totalDuration > 0 {
                // Weighted average: sum(bitrate * duration) / sum(duration)
                let weightedSum = samples.reduce(0.0) { $0 + ($1.bitrate * $1.duration) }
                computedAvg = (weightedSum / totalDuration) / 1000.0
            } else {
                // Fallback to simple average if no durations
                let sum = samples.reduce(0.0) { $0 + $1.bitrate }
                computedAvg = (sum / Double(samples.count)) / 1000.0
            }
        }
        self.avgBitrateKbps = computedAvg

        if samples.count > 1 {
            let avgBits = computedAvg * 1000.0
            let variance = samples.reduce(0.0) { sum, sample in
                let diff = sample.bitrate - avgBits
                return sum + diff * diff
            } / Double(samples.count)
            self.stdDevKbps = sqrt(variance) / 1000.0
        } else {
            self.stdDevKbps = 0
        }
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
