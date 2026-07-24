import Testing
import Foundation
import AVFoundation
@testable import FramePeekCore

/// End-to-end loudness extraction against the golden fixture
/// (5 s, AAC 440 Hz sine audio track)
struct LoudnessExtractionTests {

    @Test func analysisEngine_includesLoudnessInResult() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-h264.mp4")

        let engine = AnalysisEngine()
        let result = try await engine.analyze(url: url, options: AnalysisOptions(includeLoudness: true))

        let loudness = try #require(result.loudness)
        #expect(loudness.integratedLUFS?.isFinite == true)
    }

    @Test func goldenFixture_producesFiniteLoudness() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-h264.mp4")

        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)

        var result: LoudnessResult?
        var shortTermCount = 0
        for await update in analyzeLoudness(asset: asset, audioTrack: track) {
            shortTermCount += update.appendedShortTermSamples.count
            if let final = update.result {
                result = final
            }
        }

        let final = try #require(result)
        let integrated = try #require(final.integratedLUFS)
        #expect(integrated.isFinite)
        #expect(integrated > -70 && integrated < 0)
        let peak = try #require(final.truePeakDBTP)
        #expect(peak.isFinite && peak < 0)
        #expect(shortTermCount > 0)
    }
}
