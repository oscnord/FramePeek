import Testing
import Foundation
@testable import FramePeekCore

/// Parses the committed golden HLS ladder (Fixtures/hls/), generated from
/// golden-h264.mp4 with:
///
/// ffmpeg -i ../golden-h264.mp4 \
///   -filter_complex "[0:v]split=2[v1][v2];[v1]scale=640:360[v1out];[v2]scale=320:180[v2out]" \
///   -map "[v1out]" -map 0:a -map "[v2out]" -map 0:a \
///   -c:v libx264 -profile:v main -b:v:0 800k -b:v:1 300k \
///   -force_key_frames "expr:gte(t,n_forced*2)" -sc_threshold 0 \
///   -c:a aac -b:a 96k \
///   -f hls -hls_segment_type fmp4 -hls_time 2 -hls_playlist_type vod \
///   -hls_flags independent_segments -master_pl_name master.m3u8 \
///   -var_stream_map "v:0,a:0 v:1,a:1" stream_%v.m3u8
struct HLSFixtureTests {

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hls")
    }

    @Test func masterPlaylist_parsesLadder() throws {
        let url = fixtureDirectory.appendingPathComponent("master.m3u8")
        let text = try String(contentsOf: url, encoding: .utf8)

        guard case .multivariant(let master) = HLSPlaylistParser.parse(text) else {
            Issue.record("Expected multivariant playlist")
            return
        }

        #expect(master.warnings.isEmpty)
        #expect(master.variants.count == 2)

        let top = try #require(master.variants.first)
        #expect(top.resolutionWidth == 640)
        #expect(top.resolutionHeight == 360)
        #expect(top.bandwidth > top.averageBandwidth ?? 0)
        #expect(top.codecs.contains { $0.hasPrefix("avc1.") })
        #expect(top.codecs.contains { $0.hasPrefix("mp4a.") })

        for variant in master.variants {
            let resolved = try #require(HLSPlaylistParser.resolveURI(variant.uri, against: url))
            #expect(FileManager.default.fileExists(atPath: resolved.path))
        }
    }

    @Test func mediaPlaylists_parseSegmentsAndInitSegments() throws {
        for name in ["stream_0.m3u8", "stream_1.m3u8"] {
            let url = fixtureDirectory.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)

            guard case .media(let media) = HLSPlaylistParser.parse(text) else {
                Issue.record("Expected media playlist for \(name)")
                return
            }

            #expect(media.warnings.isEmpty)
            #expect(media.isVOD)
            #expect(media.targetDuration == 2)
            #expect(media.segments.count == 3)
            #expect(media.keys.isEmpty)

            let initURI = try #require(media.initSegmentURI)
            let initURL = try #require(HLSPlaylistParser.resolveURI(initURI, against: url))
            #expect(FileManager.default.fileExists(atPath: initURL.path))

            for segment in media.segments {
                #expect(segment.duration > 0)
                let segURL = try #require(HLSPlaylistParser.resolveURI(segment.uri, against: url))
                #expect(FileManager.default.fileExists(atPath: segURL.path))
            }

            let total = media.segments.reduce(0) { $0 + $1.duration }
            #expect(abs(total - 5.0) < 0.1)
        }
    }
}
