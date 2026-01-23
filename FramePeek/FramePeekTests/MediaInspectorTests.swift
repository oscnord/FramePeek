import Testing
import Foundation
@testable import FramePeek

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
