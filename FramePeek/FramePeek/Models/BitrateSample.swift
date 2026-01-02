import Foundation

struct BitrateSample: Identifiable {
    let id = UUID()
    let time: Double        // seconds (end time of this sample window)
    let bitrate: Double     // bits per second
    let duration: Double    // duration of this sample window in seconds (for weighted averaging)
    
    init(time: Double, bitrate: Double, duration: Double = 0) {
        self.time = time
        self.bitrate = bitrate
        self.duration = duration
    }
}
