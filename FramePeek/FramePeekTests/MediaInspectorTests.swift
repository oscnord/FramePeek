import Testing
import Foundation
@testable import FramePeek

// MARK: - ExtendedVideoInfo Tests

struct ExtendedVideoInfoTests {

    // Helper to create a minimal ExtendedVideoInfo for testing
    private func makeVideoInfo(
        frameRate: String = "23.976 fps",
        duration: String = "120.5",
        resolution: String = "1920x1080",
        hdrFormat: String? = nil,
        colorPrimaries: String? = nil
    ) -> ExtendedVideoInfo {
        ExtendedVideoInfo(
            fileName: "test.mp4",
            fileSize: "100 MB",
            fileSizeBytes: 100_000_000,
            overallBitrate: "10 Mb/s",
            duration: duration,
            durationFormatted: "2m 00s",
            containerFormat: "MP4",
            containerFormatProfile: nil,
            codecIdRaw: "avc1",
            resolution: resolution,
            displayAspectRatio: "16:9",
            frameRate: frameRate,
            codec: "H.264",
            codecProfile: "High@L4.0",
            codecIdInfo: nil,
            orientationDegrees: nil,
            trackBitrate: nil,
            maxBitrate: nil,
            minBitrate: nil,
            pixelAspectRatio: nil,
            cleanAperture: nil,
            scanType: nil,
            frameRateMode: "CFR",
            colorSpace: nil,
            chromaSubsampling: "4:2:0",
            bitsPerPixelFrame: nil,
            videoStreamSize: nil,
            colorPrimaries: colorPrimaries,
            transferFunction: nil,
            matrixCoefficients: nil,
            colorRange: nil,
            bitDepth: "8-bit",
            hdrFormat: hdrFormat,
            av1CSize: nil,
            av1Profile: nil,
            av1Level: nil,
            av1ChromaSubsampling: nil,
            av1FullRange: nil,
            creationDate: nil,
            metadataTitle: nil,
            metadataArtist: nil,
            metadataEncoder: nil,
            metadataDescription: nil,
            audioTracks: []
        )
    }

    @Test func nominalFrameRate_parsesStandardFormats() {
        #expect(makeVideoInfo(frameRate: "23.976 fps").nominalFrameRate == 23.976)
        #expect(makeVideoInfo(frameRate: "29.97 fps").nominalFrameRate == 29.97)
        #expect(makeVideoInfo(frameRate: "30 fps").nominalFrameRate == 30)
        #expect(makeVideoInfo(frameRate: "60 fps").nominalFrameRate == 60)
        #expect(makeVideoInfo(frameRate: "24 fps").nominalFrameRate == 24)
    }

    @Test func nominalFrameRate_handlesVariousFormats() {
        #expect(makeVideoInfo(frameRate: "25").nominalFrameRate == 25)
        #expect(makeVideoInfo(frameRate: "  30 fps  ").nominalFrameRate == 30)
    }

    @Test func nominalFrameRate_returnsNilForInvalid() {
        #expect(makeVideoInfo(frameRate: "").nominalFrameRate == nil)
        #expect(makeVideoInfo(frameRate: "fps").nominalFrameRate == nil)
        #expect(makeVideoInfo(frameRate: "variable").nominalFrameRate == nil)
    }

    @Test func durationSeconds_parsesValidDurations() {
        #expect(makeVideoInfo(duration: "120.5").durationSeconds == 120.5)
        #expect(makeVideoInfo(duration: "0").durationSeconds == 0)
        #expect(makeVideoInfo(duration: "3600").durationSeconds == 3600)
    }

    @Test func durationSeconds_returnsNilForInvalid() {
        #expect(makeVideoInfo(duration: "").durationSeconds == nil)
        #expect(makeVideoInfo(duration: "invalid").durationSeconds == nil)
    }

    @Test func resolutionComponents_parsesStandardFormats() {
        let info1 = makeVideoInfo(resolution: "1920x1080")
        #expect(info1.resolutionComponents?.width == 1920)
        #expect(info1.resolutionComponents?.height == 1080)

        let info2 = makeVideoInfo(resolution: "3840x2160")
        #expect(info2.resolutionComponents?.width == 3840)
        #expect(info2.resolutionComponents?.height == 2160)
    }

    @Test func resolutionComponents_handlesUnicodeMultiply() {
        let info = makeVideoInfo(resolution: "1920×1080")
        #expect(info.resolutionComponents?.width == 1920)
        #expect(info.resolutionComponents?.height == 1080)
    }

    @Test func resolutionComponents_handlesSpaces() {
        let info = makeVideoInfo(resolution: " 1920 x 1080 ")
        #expect(info.resolutionComponents?.width == 1920)
        #expect(info.resolutionComponents?.height == 1080)
    }

    @Test func resolutionComponents_returnsNilForInvalid() {
        #expect(makeVideoInfo(resolution: "").resolutionComponents == nil)
        #expect(makeVideoInfo(resolution: "1920").resolutionComponents == nil)
        #expect(makeVideoInfo(resolution: "invalid").resolutionComponents == nil)
    }

    @Test func isHDR_detectsHDRFormats() {
        #expect(makeVideoInfo(hdrFormat: "HDR10").isHDR == true)
        #expect(makeVideoInfo(hdrFormat: "Dolby Vision").isHDR == true)
        #expect(makeVideoInfo(hdrFormat: "HLG").isHDR == true)
    }

    @Test func isHDR_returnsFalseForSDR() {
        #expect(makeVideoInfo(hdrFormat: nil).isHDR == false)
        #expect(makeVideoInfo(hdrFormat: "").isHDR == false)
    }

    @Test func isWideGamut_detectsBT2020() {
        #expect(makeVideoInfo(colorPrimaries: "BT.2020").isWideGamut == true)
        #expect(makeVideoInfo(colorPrimaries: "bt2020").isWideGamut == true)
        #expect(makeVideoInfo(colorPrimaries: "ITU-R BT.2020").isWideGamut == true)
    }

    @Test func isWideGamut_detectsP3() {
        #expect(makeVideoInfo(colorPrimaries: "Display P3").isWideGamut == true)
        #expect(makeVideoInfo(colorPrimaries: "DCI-P3").isWideGamut == true)
    }

    @Test func isWideGamut_returnsFalseForStandardGamut() {
        #expect(makeVideoInfo(colorPrimaries: "BT.709").isWideGamut == false)
        #expect(makeVideoInfo(colorPrimaries: nil).isWideGamut == false)
    }
}

// MARK: - GOPStructureType Tests

struct GOPStructureTypeTests {

    @Test func isFixed_returnsTrueForFixed() {
        let fixed = GOPStructureType.fixed(frameCount: 60)
        #expect(fixed.isFixed == true)
    }

    @Test func isFixed_returnsFalseForVariable() {
        #expect(GOPStructureType.variable.isFixed == false)
        #expect(GOPStructureType.unknown.isFixed == false)
    }

    @Test func fixedFrameCount_returnsCountForFixed() {
        let fixed = GOPStructureType.fixed(frameCount: 60)
        #expect(fixed.fixedFrameCount == 60)
    }

    @Test func fixedFrameCount_returnsNilForNonFixed() {
        #expect(GOPStructureType.variable.fixedFrameCount == nil)
        #expect(GOPStructureType.unknown.fixedFrameCount == nil)
    }
}

// MARK: - FrameInfo Tests

struct FrameInfoTests {

    @Test func frameInfo_initializesCorrectly() {
        let frame = FrameInfo(time: 1.5, type: .i)
        #expect(frame.time == 1.5)
        #expect(frame.type == .i)
    }

    @Test func frameType_rawValues() {
        #expect(FrameType.i.rawValue == "I")
        #expect(FrameType.p.rawValue == "P")
        #expect(FrameType.b.rawValue == "B")
        #expect(FrameType.unknown.rawValue == "?")
    }
}

// MARK: - SyncStatus Tests

struct SyncStatusTests {

    @Test func syncStatus_displayNames() {
        #expect(SyncStatus.inSync.displayName == String(localized: "In Sync"))
        #expect(SyncStatus.minorOffset.displayName == String(localized: "Minor Offset"))
        #expect(SyncStatus.significantOffset.displayName == String(localized: "Significant Offset"))
        #expect(SyncStatus.noAudio.displayName == String(localized: "No Audio"))
    }
}

// MARK: - FramePatternUtils Tests

struct FramePatternUtilsTests {

    @Test func synthesizeIBBPFrameType_firstFrameIsI() {
        #expect(synthesizeIBBPFrameType(at: 0) == .i)
    }

    @Test func synthesizeIBBPFrameType_followsIBBPPattern() {
        // Pattern: I B B P B B P B B P ...
        #expect(synthesizeIBBPFrameType(at: 0) == .i)
        #expect(synthesizeIBBPFrameType(at: 1) == .b)
        #expect(synthesizeIBBPFrameType(at: 2) == .b)
        #expect(synthesizeIBBPFrameType(at: 3) == .p)
        #expect(synthesizeIBBPFrameType(at: 4) == .b)
        #expect(synthesizeIBBPFrameType(at: 5) == .b)
        #expect(synthesizeIBBPFrameType(at: 6) == .p)
        #expect(synthesizeIBBPFrameType(at: 7) == .b)
        #expect(synthesizeIBBPFrameType(at: 8) == .b)
        #expect(synthesizeIBBPFrameType(at: 9) == .p)
    }

    @Test func synthesizeGOPFrames_generatesCorrectCount() {
        let frames = synthesizeGOPFrames(startTime: 0, frameCount: 10, gopDuration: 1.0)
        #expect(frames.count == 10)
    }

    @Test func synthesizeGOPFrames_firstFrameIsIFrame() {
        let frames = synthesizeGOPFrames(startTime: 0, frameCount: 10, gopDuration: 1.0)
        #expect(frames.first?.type == .i)
    }

    @Test func synthesizeGOPFrames_calculatesCorrectTimes() {
        let frames = synthesizeGOPFrames(startTime: 0, frameCount: 10, gopDuration: 1.0)
        // Frame duration = 1.0 / 10 = 0.1 seconds
        #expect(frames[0].time == 0.0)
        #expect(abs(frames[1].time - 0.1) < 0.001)
        #expect(abs(frames[5].time - 0.5) < 0.001)
        #expect(abs(frames[9].time - 0.9) < 0.001)
    }

    @Test func synthesizeGOPFrames_handlesOffset() {
        let frames = synthesizeGOPFrames(startTime: 5.0, frameCount: 10, gopDuration: 1.0)
        #expect(frames[0].time == 5.0)
        #expect(abs(frames[9].time - 5.9) < 0.001)
    }

    @Test func synthesizeGOPFrames_returnsEmptyForInvalidInput() {
        #expect(synthesizeGOPFrames(startTime: 0, frameCount: 0, gopDuration: 1.0).isEmpty)
        #expect(synthesizeGOPFrames(startTime: 0, frameCount: 10, gopDuration: 0).isEmpty)
        #expect(synthesizeGOPFrames(startTime: 0, frameCount: -1, gopDuration: 1.0).isEmpty)
    }

    @Test func calculateGOPsInWindow_findsCorrectRange() {
        // 60 second video, 2 second GOPs = 30 GOPs (indices 0-29)
        let range = calculateGOPsInWindow(
            windowStart: 5.0,
            windowEnd: 15.0,
            gopDuration: 2.0,
            videoDuration: 60.0
        )
        // floor(5/2)=2, ceil(15/2)=8, capped at 29
        // GOPs 2 (4-6), 3 (6-8), 4 (8-10), 5 (10-12), 6 (12-14), 7 (14-16) overlap
        #expect(range != nil)
        #expect(range?.lowerBound == 2)
        #expect(range?.upperBound == 8)  // ceil(15/2) = 8
    }

    @Test func calculateGOPsInWindow_handlesStartOfVideo() {
        let range = calculateGOPsInWindow(
            windowStart: 0.0,
            windowEnd: 5.0,
            gopDuration: 2.0,
            videoDuration: 60.0
        )
        #expect(range?.lowerBound == 0)
    }

    @Test func calculateGOPsInWindow_handlesEndOfVideo() {
        let range = calculateGOPsInWindow(
            windowStart: 55.0,
            windowEnd: 65.0,  // Past video end
            gopDuration: 2.0,
            videoDuration: 60.0
        )
        // Should cap at last GOP
        #expect(range?.upperBound == 29)
    }

    @Test func calculateGOPsInWindow_returnsNilForInvalidInput() {
        #expect(calculateGOPsInWindow(windowStart: 0, windowEnd: 10, gopDuration: 0, videoDuration: 60) == nil)
        #expect(calculateGOPsInWindow(windowStart: 0, windowEnd: 10, gopDuration: 2, videoDuration: 0) == nil)
    }

    @Test func extrapolateFramesForWindow_generatesFramesInWindow() {
        let frames = extrapolateFramesForWindow(
            windowStart: 0.0,
            windowEnd: 2.0,
            gopDuration: 2.0,
            frameCount: 60,
            videoDuration: 120.0
        )
        // Window 0-2 includes GOP 0 (0-2), and maybe partial of GOP 1
        // Frame duration = 2.0/60 = 0.0333s
        // Frames at times 0, 0.033, 0.066... up to 1.967 are in window [0, 2)
        // All 60 frames of GOP 0 have time < 2.0, so they should be included
        #expect(frames.count >= 60)
        #expect(frames.count <= 120)  // At most 2 GOPs worth
    }

    @Test func extrapolateFramesForWindow_framesAreWithinWindow() {
        let frames = extrapolateFramesForWindow(
            windowStart: 5.0,
            windowEnd: 7.0,
            gopDuration: 2.0,
            frameCount: 60,
            videoDuration: 120.0
        )
        for frame in frames {
            #expect(frame.time >= 5.0)
            #expect(frame.time <= 7.0)
        }
    }

    @Test func extrapolateFramesForWindow_respectsVideoDuration() {
        let frames = extrapolateFramesForWindow(
            windowStart: 115.0,
            windowEnd: 125.0,  // Past video end
            gopDuration: 2.0,
            frameCount: 60,
            videoDuration: 120.0
        )
        for frame in frames {
            #expect(frame.time < 120.0)
        }
    }

    @Test func extrapolateFramesForWindow_usesProvidedPattern() {
        // Create a custom pattern: all P-frames except first
        let customPattern = [
            FrameInfo(time: 0, type: .i),
            FrameInfo(time: 0.1, type: .p),
            FrameInfo(time: 0.2, type: .p),
            FrameInfo(time: 0.3, type: .p)
        ]

        let frames = extrapolateFramesForWindow(
            windowStart: 0.0,
            windowEnd: 1.0,
            gopDuration: 1.0,
            frameCount: 4,
            videoDuration: 10.0,
            framePattern: customPattern
        )

        #expect(frames[0].type == .i)
        #expect(frames[1].type == .p)
        #expect(frames[2].type == .p)
        #expect(frames[3].type == .p)
    }

    @Test func extrapolateFramesForWindow_returnsEmptyForInvalidInput() {
        #expect(extrapolateFramesForWindow(
            windowStart: 0, windowEnd: 10, gopDuration: 0, frameCount: 60, videoDuration: 120
        ).isEmpty)
        #expect(extrapolateFramesForWindow(
            windowStart: 0, windowEnd: 10, gopDuration: 2, frameCount: 0, videoDuration: 120
        ).isEmpty)
        #expect(extrapolateFramesForWindow(
            windowStart: 0, windowEnd: 10, gopDuration: 2, frameCount: 60, videoDuration: 0
        ).isEmpty)
    }

    @Test func extrapolateFramesForWindow_framesSortedByTime() {
        let frames = extrapolateFramesForWindow(
            windowStart: 0.0,
            windowEnd: 5.0,
            gopDuration: 2.0,
            frameCount: 60,
            videoDuration: 120.0
        )

        for i in 1..<frames.count {
            #expect(frames[i].time >= frames[i-1].time)
        }
    }
}

// MARK: - GOPSegment Tests

struct GOPSegmentTests {

    @Test func gopSegment_duration() {
        let segment = GOPSegment(startTime: 1.0, endTime: 3.0, frameCount: 60, frames: nil)
        #expect(segment.duration == 2.0)
    }

    @Test func gopSegment_durationNeverNegative() {
        let segment = GOPSegment(startTime: 3.0, endTime: 1.0, frameCount: 60, frames: nil)
        #expect(segment.duration == 0)
    }
}

// MARK: - FormatUtils Tests

struct FormatUtilsTests {

    @Test func fourCCToString_convertsValidCodes() {
        #expect(fourCCToString(0x61766331) == "avc1")
        #expect(fourCCToString(0x68766331) == "hvc1")
        #expect(fourCCToString(0x61763031) == "av01")
    }

    @Test func formatDuration_formatsHours() {
        #expect(formatDuration(seconds: 3661.5) == "1h 01m 01s")
        #expect(formatDuration(seconds: 7200) == "2h 00m 00s")
    }

    @Test func formatDuration_formatsMinutes() {
        #expect(formatDuration(seconds: 125) == "2m 05s")
        #expect(formatDuration(seconds: 60) == "1m 00s")
    }

    @Test func formatDuration_formatsSeconds() {
        #expect(formatDuration(seconds: 5.5) == "5.50s")
        #expect(formatDuration(seconds: 0.25) == "0.25s")
    }

    @Test func formatDuration_handlesEdgeCases() {
        #expect(formatDuration(seconds: 0) == "0s")
        #expect(formatDuration(seconds: -1) == "N/A")
        #expect(formatDuration(seconds: Double.nan) == "N/A")
        #expect(formatDuration(seconds: Double.infinity) == "N/A")
    }

    @Test func channelLayoutDescription_returnsCorrectLayouts() {
        #expect(channelLayoutDescription(channels: 1) == "Mono")
        #expect(channelLayoutDescription(channels: 2) == "Stereo")
        #expect(channelLayoutDescription(channels: 6) == "5.1")
        #expect(channelLayoutDescription(channels: 8) == "7.1")
        #expect(channelLayoutDescription(channels: 12) == "12 channels")
    }

    @Test func audioCodecName_mapsKnownCodecs() {
        #expect(audioCodecName("aac ") == "AAC")
        #expect(audioCodecName("mp4a") == "AAC")
        #expect(audioCodecName("ac-3") == "Dolby Digital (AC-3)")
        #expect(audioCodecName("ec-3") == "Dolby Digital Plus (E-AC-3)")
        #expect(audioCodecName("alac") == "Apple Lossless")
    }

    @Test func audioCodecName_returnsUnknownCodecsTrimmed() {
        #expect(audioCodecName("unkn") == "unkn")
        #expect(audioCodecName("test ") == "test")
    }

    @Test func videoCodecName_mapsKnownCodecs() {
        #expect(videoCodecName("avc1") == "H.264")
        #expect(videoCodecName("hvc1") == "HEVC (H.265)")
        #expect(videoCodecName("av01") == "AV1")
        #expect(videoCodecName("vp09") == "VP9")
        #expect(videoCodecName("apch") == "ProRes 422 HQ")
    }

    @Test func videoCodecName_returnsUnknownAsIs() {
        #expect(videoCodecName("xxxx") == "xxxx")
    }
}

// MARK: - AspectRatioUtils Tests

struct AspectRatioUtilsTests {

    @Test func gcd_calculatesCorrectly() {
        #expect(gcd(16, 9) == 1)
        #expect(gcd(1920, 1080) == 120)
        #expect(gcd(100, 50) == 50)
        #expect(gcd(17, 13) == 1)
    }

    @Test func gcd_handlesEdgeCases() {
        #expect(gcd(0, 5) == 5)
        #expect(gcd(5, 0) == 5)
        #expect(gcd(1, 1) == 1)
    }

    @Test func calculateDisplayAspectRatio_detectsCommonRatios() {
        #expect(calculateDisplayAspectRatio(width: 1920, height: 1080) == "16:9")
        #expect(calculateDisplayAspectRatio(width: 1280, height: 720) == "16:9")
        #expect(calculateDisplayAspectRatio(width: 640, height: 480) == "4:3")
        #expect(calculateDisplayAspectRatio(width: 1080, height: 1080) == "1:1")
    }

    @Test func calculateDisplayAspectRatio_handlesVertical() {
        #expect(calculateDisplayAspectRatio(width: 1080, height: 1920) == "9:16 (Vertical)")
    }

    @Test func calculateDisplayAspectRatio_handlesPAR() {
        // Anamorphic 1920x1080 with 4:3 PAR should be wider
        let result = calculateDisplayAspectRatio(width: 1440, height: 1080, parH: 4, parV: 3)
        #expect(result == "16:9")
    }

    @Test func calculateDisplayAspectRatio_handlesInvalidInput() {
        #expect(calculateDisplayAspectRatio(width: 0, height: 1080) == "N/A")
        #expect(calculateDisplayAspectRatio(width: 1920, height: 0) == "N/A")
        #expect(calculateDisplayAspectRatio(width: -1, height: 1080) == "N/A")
    }

    @Test func isVerticalResolution_detectsOrientation() {
        #expect(isVerticalResolution(width: 1080, height: 1920) == true)
        #expect(isVerticalResolution(width: 1920, height: 1080) == false)
        #expect(isVerticalResolution(width: 1080, height: 1080) == false)
    }

    @Test func resolutionCategory_classifiesCorrectly() {
        #expect(resolutionCategory(width: 640, height: 480) == "SD")
        #expect(resolutionCategory(width: 1280, height: 720) == "HD (720p)")
        #expect(resolutionCategory(width: 1920, height: 1080) == "Full HD (1080p)")
        #expect(resolutionCategory(width: 2560, height: 1440) == "QHD (1440p)")
        #expect(resolutionCategory(width: 3840, height: 2160) == "4K UHD")
        #expect(resolutionCategory(width: 7680, height: 4320) == "8K UHD")
    }

    @Test func resolutionCategory_usesMinDimension() {
        // Vertical 4K (2160x3840) should use min dimension (2160) -> 4K UHD
        #expect(resolutionCategory(width: 2160, height: 3840) == "4K UHD")
    }
}

// MARK: - AV1Parser Tests

struct AV1ParserTests {

    @Test func parseAV1C_parsesMainProfile() {
        // Main profile (0), level 5.1, 8-bit, 4:2:0
        let data = Data([0x81, 0b0001_0011, 0b0000_1100, 0x00])
        let result = parseAV1C(data)

        #expect(result != nil)
        #expect(result?.profile == 0)
        #expect(result?.level == 19) // 5.1
        #expect(result?.bitDepth == 8)
        #expect(result?.chromaSubsampling == "4:2:0")
    }

    @Test func parseAV1C_parsesHighProfile10Bit() {
        // High profile (1), level 4.0, 10-bit, 4:4:4
        let data = Data([0x81, UInt8(0b0010_0000 | 0b0001_0000), 0b0100_0000, 0x00])
        let result = parseAV1C(data)

        #expect(result != nil)
        #expect(result?.profile == 1)
        #expect(result?.bitDepth == 10)
        #expect(result?.chromaSubsampling == "4:4:4")
    }

    @Test func parseAV1C_parsesProfessionalProfile12Bit() {
        // Professional profile (2), 12-bit (highBitDepth=1, twelveBit=1)
        let data = Data([0x81, 0b0100_0000, 0b0110_0000, 0x00])
        let result = parseAV1C(data)

        #expect(result != nil)
        #expect(result?.profile == 2)
        #expect(result?.bitDepth == 12)
    }

    @Test func parseAV1C_parsesMonochrome() {
        let data = Data([0x81, 0x00, 0b0001_0000, 0x00])
        let result = parseAV1C(data)

        #expect(result?.chromaSubsampling == "Monochrome")
    }

    @Test func parseAV1C_parses422Chroma() {
        // 4:2:2: subsamplingX=1, subsamplingY=0
        let data = Data([0x81, 0x00, 0b0000_1000, 0x00])
        let result = parseAV1C(data)

        #expect(result?.chromaSubsampling == "4:2:2")
    }

    @Test func parseAV1C_parsesFullRange() {
        let data = Data([0x81, 0x00, 0x00, 0b1000_0000])
        let result = parseAV1C(data)

        #expect(result?.fullRange == true)
    }

    @Test func parseAV1C_returnsNilForInvalidData() {
        #expect(parseAV1C(Data()) == nil)
        #expect(parseAV1C(Data([0x81, 0x00, 0x00])) == nil) // Too short
    }

    @Test func av1LevelDescription_formatsCorrectly() {
        #expect(av1LevelDescription(0) == "2.0")
        #expect(av1LevelDescription(1) == "2.1")
        #expect(av1LevelDescription(4) == "3.0")
        #expect(av1LevelDescription(8) == "4.0")
        #expect(av1LevelDescription(12) == "5.0")
        #expect(av1LevelDescription(19) == "6.3")
    }

    @Test func av1ProfileDescription_returnsCorrectNames() {
        #expect(av1ProfileDescription(0) == "Main")
        #expect(av1ProfileDescription(1) == "High")
        #expect(av1ProfileDescription(2) == "Professional")
        #expect(av1ProfileDescription(99) == "Unknown (99)")
    }
}

// MARK: - Codec Profile Parsing Tests

struct CodecProfileParsingTests {

    @Test func parseHEVCProfile_parsesMainProfile() {
        // Main profile (1), Main tier, Level 4.0 (120)
        var data = Data(count: 13)
        data[1] = 0x01  // profile_idc = 1 (Main)
        data[12] = 120  // level_idc = 120 (Level 4.0)

        let result = parseHEVCProfile(data)
        #expect(result?.contains("Main") == true)
        #expect(result?.contains("L4.0") == true)
    }

    @Test func parseHEVCProfile_parsesMain10Profile() {
        var data = Data(count: 13)
        data[1] = 0x02  // profile_idc = 2 (Main 10)
        data[12] = 153  // level_idc = 153 (Level 5.1)

        let result = parseHEVCProfile(data)
        #expect(result?.contains("Main 10") == true)
        #expect(result?.contains("L5.1") == true)
    }

    @Test func parseHEVCProfile_returnsNilForShortData() {
        #expect(parseHEVCProfile(Data(count: 12)) == nil)
    }

    @Test func parseAVCProfile_parsesHighProfile() {
        var data = Data(count: 4)
        data[1] = 100  // High profile
        data[3] = 41   // Level 4.1

        let result = parseAVCProfile(data)
        #expect(result?.contains("High") == true)
        #expect(result?.contains("L4.1") == true)
    }

    @Test func parseAVCProfile_parsesBaselineProfile() {
        var data = Data(count: 4)
        data[1] = 66   // Baseline profile
        data[3] = 30   // Level 3.0

        let result = parseAVCProfile(data)
        #expect(result?.contains("Baseline") == true)
        #expect(result?.contains("L3.0") == true)
    }

    @Test func parseAVCProfile_returnsNilForShortData() {
        #expect(parseAVCProfile(Data(count: 3)) == nil)
    }

    @Test func parseVP9Profile_parsesProfile0() {
        var data = Data(count: 8)
        data[4] = 0  // Profile 0
        data[5] = 31 // Level 31

        let result = parseVP9Profile(data)
        #expect(result?.contains("Profile 0") == true)
        #expect(result?.contains("8-bit 4:2:0") == true)
    }

    @Test func parseVP9Profile_parsesProfile2() {
        var data = Data(count: 8)
        data[4] = 2  // Profile 2
        data[5] = 41 // Level 41

        let result = parseVP9Profile(data)
        #expect(result?.contains("Profile 2") == true)
        #expect(result?.contains("10/12-bit") == true)
    }

    @Test func parseVP9Profile_returnsNilForShortData() {
        #expect(parseVP9Profile(Data(count: 7)) == nil)
    }
}

// MARK: - TimeFormatting Tests

struct TimeFormattingTests {

    @Test func formatTimeForChart_formatsTimecodeCorrectly() {
        #expect(formatTimeForChart(0) == "00:00:00:00")
        #expect(formatTimeForChart(1, frameRate: 30) == "00:00:01:00")
        #expect(formatTimeForChart(60, frameRate: 30) == "00:01:00:00")
        #expect(formatTimeForChart(3600, frameRate: 30) == "01:00:00:00")
    }

    @Test func formatTimeForChart_handlesFrames() {
        // At 30fps, 0.5 seconds = 15 frames
        let result = formatTimeForChart(0.5, frameRate: 30)
        #expect(result == "00:00:00:15")
    }

    @Test func formatTimeForChart_uses30fpsDefault() {
        let result = formatTimeForChart(1.0)
        #expect(result == "00:00:01:00")
    }
}
