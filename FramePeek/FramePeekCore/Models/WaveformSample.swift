import Foundation

/// A single audio waveform sample
public struct WaveformSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Double        // seconds (time position of this sample)
    public let amplitude: Double   // normalized amplitude (0.0 to 1.0)
    public let minAmplitude: Double // minimum amplitude in this window (for stereo visualization)
    public let maxAmplitude: Double // maximum amplitude in this window

    public init(id: UUID = UUID(), time: Double, amplitude: Double, minAmplitude: Double = 0.0, maxAmplitude: Double = 0.0) {
        self.id = id
        self.time = time
        self.amplitude = amplitude
        self.minAmplitude = minAmplitude
        self.maxAmplitude = maxAmplitude
    }
}

/// Progressive update during waveform extraction
public struct WaveformUpdate: Sendable {
    public let appendedSamples: [WaveformSample]
    public let isFinished: Bool
    
    public init(appendedSamples: [WaveformSample], isFinished: Bool) {
        self.appendedSamples = appendedSamples
        self.isFinished = isFinished
    }
}
