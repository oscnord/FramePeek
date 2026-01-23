import Foundation

struct WaveformSample: Identifiable {
    let id = UUID()
    let time: Double        // seconds (time position of this sample)
    let amplitude: Double   // normalized amplitude (0.0 to 1.0)
    let minAmplitude: Double // minimum amplitude in this window (for stereo visualization)
    let maxAmplitude: Double // maximum amplitude in this window

    init(time: Double, amplitude: Double, minAmplitude: Double = 0.0, maxAmplitude: Double = 0.0) {
        self.time = time
        self.amplitude = amplitude
        self.minAmplitude = minAmplitude
        self.maxAmplitude = maxAmplitude
    }
}
