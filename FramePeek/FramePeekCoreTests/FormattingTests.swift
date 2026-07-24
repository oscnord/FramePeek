import Testing
@testable import FramePeekCore

struct FormattingTests {

    // MARK: - formatDuration

    @Test func formatDurationHandlesHoursMinutesSeconds() {
        #expect(formatDuration(seconds: 3725) == "1h 02m 05s")
    }

    @Test func formatDurationHandlesMinutesAndSeconds() {
        #expect(formatDuration(seconds: 150) == "2m 30s")
    }

    @Test func formatDurationHandlesSubMinute() {
        #expect(formatDuration(seconds: 12.34) == "12.34s")
    }

    @Test func formatDurationReturnsNAForInvalid() {
        #expect(formatDuration(seconds: -1) == "N/A")
        #expect(formatDuration(seconds: .nan) == "N/A")
        #expect(formatDuration(seconds: .infinity) == "N/A")
    }

    @Test func formatDurationZero() {
        #expect(formatDuration(seconds: 0) == "0s")
    }

    // MARK: - formatTimeForChart

    @Test func formatTimeForChartProducesTimecode() {
        // 1h 0m 0s 0f at 30fps
        #expect(formatTimeForChart(3600, frameRate: 30) == "01:00:00:00")
        // 1.5s at 30fps = 1s 15f
        #expect(formatTimeForChart(1.5, frameRate: 30) == "00:00:01:15")
    }

    @Test func formatTimeForChartDefaultsTo30fps() {
        #expect(formatTimeForChart(1.0) == "00:00:01:00")
    }

    // MARK: - channelLayoutDescription

    @Test func channelLayoutDescriptionForKnownCounts() {
        #expect(channelLayoutDescription(channels: 1) == "Mono")
        #expect(channelLayoutDescription(channels: 2) == "Stereo")
        #expect(channelLayoutDescription(channels: 6) == "5.1")
        #expect(channelLayoutDescription(channels: 8) == "7.1")
    }

    @Test func channelLayoutDescriptionForUnknownCount() {
        #expect(channelLayoutDescription(channels: 12) == "12 channels")
    }

    // MARK: - calculateDisplayAspectRatio

    @Test func aspectRatioMatchesCommonRatios() {
        #expect(calculateDisplayAspectRatio(width: 1920, height: 1080) == "16:9")
        #expect(calculateDisplayAspectRatio(width: 640, height: 480) == "4:3")
        #expect(calculateDisplayAspectRatio(width: 1080, height: 1080) == "1:1")
    }

    @Test func aspectRatioReturnsNAForInvalid() {
        #expect(calculateDisplayAspectRatio(width: 0, height: 0) == "N/A")
        #expect(calculateDisplayAspectRatio(width: 1920, height: 0) == "N/A")
    }

    @Test func aspectRatioRespectsPixelAspectRatio() {
        // Anamorphic 720x480 with PAR 32:27 ≈ 16:9 display
        let result = calculateDisplayAspectRatio(width: 720, height: 480, parH: 32, parV: 27)
        #expect(result == "16:9")
    }

    // MARK: - resolutionCategory

    @Test func resolutionCategoryClassifiesStandardResolutions() {
        #expect(resolutionCategory(width: 1920, height: 1080) == "Full HD (1080p)")
        #expect(resolutionCategory(width: 1280, height: 720) == "HD (720p)")
        #expect(resolutionCategory(width: 3840, height: 2160) == "4K UHD")
        #expect(resolutionCategory(width: 7680, height: 4320) == "8K UHD")
    }

    @Test func resolutionCategoryUsesSmallerDimension() {
        // Vertical 1080x1920 should still classify as 1080p
        #expect(resolutionCategory(width: 1080, height: 1920) == "Full HD (1080p)")
    }

    // MARK: - gcd

    @Test func gcdProducesGreatestCommonDivisor() {
        #expect(gcd(12, 18) == 6)
        #expect(gcd(100, 75) == 25)
        #expect(gcd(7, 13) == 1)
        #expect(gcd(0, 5) == 5)
    }

    // MARK: - isVerticalResolution

    @Test func isVerticalResolutionDetectsPortrait() {
        #expect(isVerticalResolution(width: 1080, height: 1920) == true)
        #expect(isVerticalResolution(width: 1920, height: 1080) == false)
        #expect(isVerticalResolution(width: 1080, height: 1080) == false)
    }
}
