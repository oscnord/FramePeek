import Foundation

// MARK: - Loudness Measurement (EBU R128 / ITU-R BS.1770-4)

/// A short-term loudness reading for charting (3 s window per EBU Tech 3341)
public struct LoudnessSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Double     // seconds (window end position)
    public let lufs: Double

    public init(id: UUID = UUID(), time: Double, lufs: Double) {
        self.id = id
        self.time = time
        self.lufs = lufs
    }
}

/// Aggregate loudness measurement for one audio track
public struct LoudnessResult: Codable, Sendable {
    /// Gated integrated loudness per BS.1770-4 (nil when everything gated out)
    public let integratedLUFS: Double?
    /// Loudness range per EBU Tech 3342 (nil when insufficient data)
    public let loudnessRangeLU: Double?
    /// True peak per BS.1770-4 Annex 2, 4x oversampled (nil for silence)
    public let truePeakDBTP: Double?
    public let maxMomentaryLUFS: Double?
    public let maxShortTermLUFS: Double?
    public let channelCount: Int
    public let sampleRate: Double

    public init(
        integratedLUFS: Double?,
        loudnessRangeLU: Double?,
        truePeakDBTP: Double?,
        maxMomentaryLUFS: Double?,
        maxShortTermLUFS: Double?,
        channelCount: Int,
        sampleRate: Double
    ) {
        self.integratedLUFS = integratedLUFS
        self.loudnessRangeLU = loudnessRangeLU
        self.truePeakDBTP = truePeakDBTP
        self.maxMomentaryLUFS = maxMomentaryLUFS
        self.maxShortTermLUFS = maxShortTermLUFS
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }

    /// EBU R128 program target: -23 LUFS with a +/-0.5 LU tolerance
    public var isR128Compliant: Bool? {
        guard let integrated = integratedLUFS else { return nil }
        return abs(integrated - (-23.0)) <= 0.5
    }

    /// EBU R128 maximum permitted true peak is -1 dBTP
    public var isTruePeakCompliant: Bool? {
        guard let peak = truePeakDBTP else { return nil }
        return peak <= -1.0
    }
}

/// Progressive update from loudness analysis
public struct LoudnessUpdate: Sendable {
    public let appendedShortTermSamples: [LoudnessSample]
    public let result: LoudnessResult?

    public init(appendedShortTermSamples: [LoudnessSample], result: LoudnessResult?) {
        self.appendedShortTermSamples = appendedShortTermSamples
        self.result = result
    }
}
