import Testing
import Foundation
@testable import FramePeekCore

/// End-to-end ladder analysis against the golden HLS fixture
/// (see HLSFixtureTests for the ffmpeg command that generated it).
struct HLSLadderAnalyzerTests {

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hls")
    }

    private func analyze(_ url: URL) async -> StreamingLadderAnalysis? {
        var result: StreamingLadderAnalysis?
        for await progress in analyzeHLSLadder(url: url) {
            if let final = progress.result {
                result = final
            }
        }
        return result
    }

    @Test func goldenLadder_passesAllChecks() async throws {
        let url = fixtureDirectory.appendingPathComponent("master.m3u8")
        let result = try #require(await analyze(url))

        #expect(result.isVOD)
        #expect(result.variants.count == 2)
        #expect(result.findings(withSeverity: .error).isEmpty)

        for variant in result.variants {
            let peak = try #require(variant.measuredPeakBitrate)
            let average = try #require(variant.measuredAverageBitrate)
            #expect(peak <= Double(variant.declaredBandwidth) * 1.01)
            if let declaredAverage = variant.declaredAverageBandwidth {
                #expect(abs(average - Double(declaredAverage)) / Double(declaredAverage) < 0.15)
            }
            #expect(variant.sampledSegmentCount == 3)
            #expect(!variant.keyframeTimes.isEmpty)
            #expect(!variant.isDRMProtected)

            let stats = try #require(variant.segmentStats)
            #expect(stats.count == 3)
            #expect(stats.maxDuration <= 2.001)
        }
    }

    @Test func loweredBandwidth_firesBandwidthExceededFinding() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls-negative-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixtureDirectory, to: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let masterURL = tempDir.appendingPathComponent("master.m3u8")
        var master = try String(contentsOf: masterURL, encoding: .utf8)
        master = master.replacingOccurrences(
            of: #"BANDWIDTH=\d+"#,
            with: "BANDWIDTH=100000",
            options: .regularExpression
        )
        try master.write(to: masterURL, atomically: true, encoding: .utf8)

        let result = try #require(await analyze(masterURL))
        let bandwidthErrors = result.findings.filter { $0.kind == "bandwidth-exceeded" }
        #expect(bandwidthErrors.count == 2)
        #expect(bandwidthErrors.allSatisfy { $0.severity == .error })
    }

    @Test func extinfExceedingTargetDuration_firesFinding() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls-extinf-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixtureDirectory, to: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaURL = tempDir.appendingPathComponent("stream_0.m3u8")
        var media = try String(contentsOf: mediaURL, encoding: .utf8)
        media = media.replacingOccurrences(of: "#EXT-X-TARGETDURATION:2", with: "#EXT-X-TARGETDURATION:1")
        try media.write(to: mediaURL, atomically: true, encoding: .utf8)

        let result = try #require(await analyze(tempDir.appendingPathComponent("master.m3u8")))
        #expect(result.findings.contains { $0.kind == "segment-exceeds-target-duration" })
    }

    @Test func mediaPlaylistURL_analyzedAsSingleVariant() async throws {
        let url = fixtureDirectory.appendingPathComponent("stream_1.m3u8")
        let result = try #require(await analyze(url))

        #expect(result.variants.count == 1)
        #expect(result.findings.contains { $0.kind == "not-multivariant" })
        #expect(result.variants[0].measuredAverageBitrate != nil)
        #expect(result.findings(withSeverity: .error).isEmpty)
    }

    @Test func unreachablePlaylist_reportsErrorFinding() async throws {
        let url = URL(fileURLWithPath: "/nonexistent/master.m3u8")
        let result = try #require(await analyze(url))
        #expect(result.variants.isEmpty)
        #expect(result.findings.contains { $0.kind == "playlist-unreachable" && $0.severity == .error })
    }
}
