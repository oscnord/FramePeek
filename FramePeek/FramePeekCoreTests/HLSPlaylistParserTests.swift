import Testing
import Foundation
@testable import FramePeekCore

struct HLSPlaylistParserTests {

    // MARK: Multivariant

    @Test func multivariant_parsesVariantsWithAllAttributes() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=YES,URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,AVERAGE-BANDWIDTH=1800000,RESOLUTION=1280x720,FRAME-RATE=25.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud"
        720p/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.64001e,mp4a.40.2",AUDIO="aud"
        360p/index.m3u8
        """

        guard case .multivariant(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected multivariant playlist")
            return
        }

        #expect(result.warnings.isEmpty)
        #expect(result.variants.count == 2)

        let top = try #require(result.variants.first)
        #expect(top.bandwidth == 2_000_000)
        #expect(top.averageBandwidth == 1_800_000)
        #expect(top.resolutionWidth == 1280)
        #expect(top.resolutionHeight == 720)
        #expect(top.frameRate == 25.0)
        #expect(top.codecs == ["avc1.640028", "mp4a.40.2"])
        #expect(top.uri == "720p/index.m3u8")
        #expect(top.audioGroupID == "aud")

        let rendition = try #require(result.renditions.first)
        #expect(rendition.type == "AUDIO")
        #expect(rendition.groupID == "aud")
        #expect(rendition.language == "en")
        #expect(rendition.uri == "audio/en.m3u8")
        #expect(rendition.isDefault)
    }

    @Test func multivariant_streamInfWithoutURI_warnsAndSkips() {
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000000
        #EXT-X-STREAM-INF:BANDWIDTH=2000000
        variant.m3u8
        """

        guard case .multivariant(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected multivariant playlist")
            return
        }
        #expect(result.variants.count == 1)
        #expect(result.variants[0].bandwidth == 2_000_000)
        #expect(result.warnings.contains { $0.contains("without a following URI") })
    }

    @Test func multivariant_missingBandwidth_warns() {
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:RESOLUTION=1280x720
        variant.m3u8
        """

        guard case .multivariant(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected multivariant playlist")
            return
        }
        #expect(result.variants.count == 1)
        #expect(result.variants[0].bandwidth == 0)
        #expect(result.warnings.contains { $0.contains("BANDWIDTH") })
    }

    // MARK: Media playlist

    @Test func media_parsesSegmentsAndTags() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:4
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://example"
        #EXTINF:4.004,
        seg0.m4s
        #EXTINF:4.004,segment title
        seg1.m4s
        #EXT-X-DISCONTINUITY
        #EXTINF:2.002,
        seg2.m4s
        #EXT-X-ENDLIST
        """

        guard case .media(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected media playlist")
            return
        }

        #expect(result.warnings.isEmpty)
        #expect(result.version == 7)
        #expect(result.targetDuration == 4)
        #expect(result.playlistType == "VOD")
        #expect(result.hasEndList)
        #expect(result.isVOD)
        #expect(result.initSegmentURI == "init.mp4")
        #expect(result.initSegmentByteRange == HLSByteRange(length: 720, offset: 0))

        let key = try #require(result.keys.first)
        #expect(key.method == "SAMPLE-AES")
        #expect(key.isDRM)

        #expect(result.segments.count == 3)
        #expect(result.segments[0] == HLSSegment(uri: "seg0.m4s", duration: 4.004, byteRange: nil, discontinuityBefore: false))
        #expect(result.segments[1].duration == 4.004)
        #expect(result.segments[2].discontinuityBefore)
    }

    @Test func media_byteRangeAppliesToNextSegmentOnly() {
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXTINF:4.0,
        #EXT-X-BYTERANGE:1000@500
        all.ts
        #EXTINF:4.0,
        all2.ts
        """

        guard case .media(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected media playlist")
            return
        }
        #expect(result.segments[0].byteRange == HLSByteRange(length: 1000, offset: 500))
        #expect(result.segments[1].byteRange == nil)
    }

    @Test func media_liveWithoutEndList_isNotVOD() {
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:6.0,
        seg100.ts
        """

        guard case .media(let result) = HLSPlaylistParser.parse(playlist) else {
            Issue.record("Expected media playlist")
            return
        }
        #expect(!result.isVOD)
    }

    // MARK: Malformed input (total parser)

    @Test func malformed_neverCrashes_collectsWarnings() {
        let inputs = [
            "",
            "not a playlist at all",
            "#EXTM3U\n#EXT-X-TARGETDURATION:abc\nseg.ts",
            "#EXTM3U\n#EXTINF:notanumber,\nseg.ts",
            "#EXTM3U\n#EXT-X-BYTERANGE:@@@\n#EXTINF:2,\nseg.ts",
            "#EXTM3U\n#EXT-X-KEY:URI=\"no-method\"\n#EXTINF:2,\nseg.ts",
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=öäå\nvariant.m3u8",
            "#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1280xABC,BANDWIDTH=1\nv.m3u8",
            String(repeating: "#EXT-X-DISCONTINUITY\n", count: 1000),
        ]

        for input in inputs {
            switch HLSPlaylistParser.parse(input) {
            case .multivariant, .media:
                break
            }
        }

        guard case .media(let noHeader) = HLSPlaylistParser.parse("seg.ts") else {
            Issue.record("Expected media playlist")
            return
        }
        #expect(noHeader.warnings.contains { $0.contains("#EXTM3U") })
        #expect(noHeader.warnings.contains { $0.contains("no preceding EXTINF") })
        #expect(noHeader.segments.count == 1)
        #expect(noHeader.segments[0].duration == 0)
    }

    // MARK: Attribute lists

    @Test func attributes_commasInsideQuotedStringsPreserved() {
        let attrs = HLSPlaylistParser.parseAttributes(#"CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=1000,NAME="a, b""#)
        #expect(attrs["CODECS"] == "avc1.640028,mp4a.40.2")
        #expect(attrs["BANDWIDTH"] == "1000")
        #expect(attrs["NAME"] == "a, b")
    }

    @Test func attributes_malformedPairsSkipped() {
        let attrs = HLSPlaylistParser.parseAttributes("JUNK,=novalue,GOOD=1")
        #expect(attrs["GOOD"] == "1")
        #expect(attrs.count == 1)
    }

    // MARK: URI resolution

    @Test func resolveURI_relativeAndAbsolute() throws {
        let base = try #require(URL(string: "https://cdn.example.com/vod/master.m3u8"))
        #expect(HLSPlaylistParser.resolveURI("720p/index.m3u8", against: base)?.absoluteString
                == "https://cdn.example.com/vod/720p/index.m3u8")
        #expect(HLSPlaylistParser.resolveURI("https://other.example.com/x.m3u8", against: base)?.absoluteString
                == "https://other.example.com/x.m3u8")

        let fileBase = URL(fileURLWithPath: "/tmp/hls/master.m3u8")
        #expect(HLSPlaylistParser.resolveURI("seg0.m4s", against: fileBase)?.path == "/tmp/hls/seg0.m4s")
    }

    @Test func parseByteRange_forms() {
        #expect(HLSPlaylistParser.parseByteRange("1000@500") == HLSByteRange(length: 1000, offset: 500))
        #expect(HLSPlaylistParser.parseByteRange("1000") == HLSByteRange(length: 1000, offset: nil))
        #expect(HLSPlaylistParser.parseByteRange("abc") == nil)
        #expect(HLSPlaylistParser.parseByteRange("1000@xyz") == nil)
    }
}
