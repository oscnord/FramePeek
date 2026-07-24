import Testing
import Foundation
@testable import FramePeekCore

struct CSVExporterTests {

    @Test func bitrateExportHasHeaderAndDataRows() {
        let samples = [
            BitrateSample(time: 0.0, bitrate: 1_000_000, duration: 1.0),
            BitrateSample(time: 1.0, bitrate: 2_500_000, duration: 1.0),
        ]
        let csv = CSVExporter.exportBitrate(samples)

        #expect(csv.contains("time,bitrate_kbps,duration_s"))
        #expect(csv.contains("0.000,1000.0,1.000"))
        #expect(csv.contains("1.000,2500.0,1.000"))
    }

    @Test func bitrateExportEmptySamplesProducesHeaderOnly() {
        let csv = CSVExporter.exportBitrate([])
        let lines = csv.split(separator: "\n").map(String.init)

        #expect(lines == ["time,bitrate_kbps,duration_s"])
    }

    @Test func bitrateExportPrependsFileInfoComments() {
        let info = FileInfo(path: "/x/y.mp4", name: "y.mp4", size: 1, sizeFormatted: "1 B")
        let csv = CSVExporter.exportBitrate([], fileInfo: info)

        #expect(csv.hasPrefix("# FramePeek Bitrate Analysis\n# File: y.mp4\n"))
    }

    @Test func waveformExportConvertsSamples() {
        let samples = [
            WaveformSample(time: 0.0, amplitude: 0.5, minAmplitude: -0.1, maxAmplitude: 0.6),
        ]
        let csv = CSVExporter.exportWaveform(samples, trackIndex: 2)

        #expect(csv.contains("time,amplitude,min,max"))
        #expect(csv.contains("0.000,0.5000,-0.1000,0.6000"))
    }

    @Test func bitrateDataRoundTripsThroughUTF8() {
        let samples = [BitrateSample(time: 1.5, bitrate: 500_000, duration: 0.5)]
        let data = CSVExporter.exportBitrateData(samples)
        let decoded = String(data: data, encoding: .utf8)

        #expect(decoded?.contains("1.500,500.0,0.500") == true)
    }
}
