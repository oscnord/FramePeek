import Testing
import Foundation
import AVFoundation
@testable import FramePeekCore

/// Golden-file tests for the bitrate extraction pipelines.
/// Fixtures are generated with ffmpeg (same content muxed three ways):
///   testsrc2 320x180@30, 5s, H.264 ~289 kb/s video stream + AAC audio
/// The three containers exercise the reader, fragmented-MP4, and TS paths;
/// preferAccuracy exercises reader vs cursor on the same file.
struct BitrateExtractionGoldenTests {

    private static let videoStreamBitrate = 288_876.0  // from ffprobe at fixture creation
    private static let fixtureDuration = 5.0

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    /// Mirrors the app's consumption contract: progressive batches append,
    /// the finished update supplies rawFrames for the authoritative
    /// re-aggregation (its appendedSamples are a redundant full flush)
    private func extractSamples(_ name: String, preferAccuracy: Bool = false) async -> [BitrateSample] {
        let url = fixtureURL(name)
        let asset = AVURLAsset(url: url)
        let options = FrameSamplingOptions.everyFrame(
            maxSamples: 10_000,
            emitEveryNSamples: 1_000,
            preferAccuracy: preferAccuracy
        )

        var progressive: [BitrateSample] = []
        var rawFrames: [RawFrame] = []
        var averageFPS: Double?
        for await update in extractBitratesFast(asset: asset, options: options) {
            if update.isFinished && !update.rawFrames.isEmpty {
                rawFrames = update.rawFrames.sorted { $0.pts < $1.pts }
            } else {
                progressive.append(contentsOf: update.appendedSamples)
            }
            averageFPS = update.averageFPS ?? averageFPS
            if update.isFinished { break }
        }

        guard !rawFrames.isEmpty else { return progressive }
        return aggregateFrames(rawFrames: rawFrames, mode: .second, averageFPS: averageFPS, maxSamples: 10_000)
    }

    private func weightedMeanBitrate(_ samples: [BitrateSample]) -> Double {
        let totalDuration = samples.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return 0 }
        let weightedSum = samples.reduce(0.0) { $0 + $1.bitrate * $1.duration }
        return weightedSum / totalDuration
    }

    @Test func standardMP4_matchesStreamBitrate() async {
        let samples = await extractSamples("golden-h264.mp4")

        #expect(samples.count >= 4 && samples.count <= 7)
        let mean = weightedMeanBitrate(samples)
        #expect(abs(mean - Self.videoStreamBitrate) / Self.videoStreamBitrate < 0.25)

        let coveredDuration = samples.reduce(0.0) { $0 + $1.duration }
        #expect(abs(coveredDuration - Self.fixtureDuration) < 1.5)
    }

    @Test func fragmentedMP4_matchesStreamBitrate() async {
        let samples = await extractSamples("golden-fmp4.mp4")

        #expect(samples.count >= 4 && samples.count <= 7)
        let mean = weightedMeanBitrate(samples)
        #expect(abs(mean - Self.videoStreamBitrate) / Self.videoStreamBitrate < 0.25)
    }

    @Test func mpegTS_matchesStreamBitrate() async {
        let samples = await extractSamples("golden.ts")

        #expect(samples.count >= 4 && samples.count <= 7)
        let mean = weightedMeanBitrate(samples)
        #expect(abs(mean - Self.videoStreamBitrate) / Self.videoStreamBitrate < 0.30)
    }

    @Test func readerPath_matchesStreamBitrate() async {
        let samples = await extractSamples("golden-h264.mp4", preferAccuracy: true)

        #expect(samples.count >= 4 && samples.count <= 7)
        let mean = weightedMeanBitrate(samples)
        #expect(abs(mean - Self.videoStreamBitrate) / Self.videoStreamBitrate < 0.25)
    }

    @Test func containersAgreeOnSameContent() async {
        let mp4 = weightedMeanBitrate(await extractSamples("golden-h264.mp4"))
        let fmp4 = weightedMeanBitrate(await extractSamples("golden-fmp4.mp4"))
        let ts = weightedMeanBitrate(await extractSamples("golden.ts"))
        let reader = weightedMeanBitrate(await extractSamples("golden-h264.mp4", preferAccuracy: true))

        #expect(mp4 > 0 && fmp4 > 0 && ts > 0 && reader > 0)
        // Same encoded frames, so per-track bitrate must agree across containers
        #expect(abs(mp4 - fmp4) / mp4 < 0.15)
        #expect(abs(mp4 - ts) / mp4 < 0.20)
        #expect(abs(mp4 - reader) / mp4 < 0.15)
    }
}
