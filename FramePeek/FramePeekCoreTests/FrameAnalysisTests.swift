import Testing
import CoreGraphics
@testable import FramePeekCore

/// Anchors for the vectorized frame analysis path: synthetic frames with
/// analytically known metrics.
struct FrameAnalysisTests {

    private func makeImage(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let (r, g, b) = pixel(x, y)
                data[offset] = r
                data[offset + 1] = g
                data[offset + 2] = b
            }
        }
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        return context.makeImage()!
    }

    @Test func solidGray_metricsMatchAnalyticValues() {
        let gray = makeImage(width: 256, height: 256) { _, _ in (128, 128, 128) }
        let result = analyzeFrame(cgImage: gray, time: 0, config: .default)

        let expected = 128.0 / 255.0
        #expect(abs(result.luminance.average - expected) < 0.01)
        #expect(abs(result.luminance.min - expected) < 0.01)
        #expect(abs(result.luminance.max - expected) < 0.01)
        #expect(abs(result.luminance.percentile02 - expected) < 0.01)
        #expect(abs(result.luminance.percentile98 - expected) < 0.01)
        #expect(result.saturation < 0.01)
        #expect(result.exposureStatus == .properlyExposed)

        // All histogram mass in one bin per channel
        #expect(result.histogram.red[128] > 0.95)
        #expect(result.histogram.green[128] > 0.95)
        #expect(result.histogram.blue[128] > 0.95)

        // Neutral gray resolves to a high-confidence daylight CCT
        #expect(result.colorTemperature != nil)
        if let cct = result.colorTemperature {
            #expect(cct.cct > 6300 && cct.cct < 6700)
            #expect(cct.confidence >= 0.9)
        }

        // Waveform: every column concentrates at the gray level
        if let waveform = result.waveformData {
            let column = waveform.columns[waveform.columns.count / 2]
            let level = Int(expected * 255.0)
            let massNearLevel = column[(level - 1)...(level + 1)].reduce(0, +)
            #expect(massNearLevel > 0.95)
        }
    }

    @Test func blackWhiteSplit_detectsClippingAndFullRange() {
        let split = makeImage(width: 256, height: 256) { x, _ in
            x < 128 ? (0, 0, 0) : (255, 255, 255)
        }
        let result = analyzeFrame(cgImage: split, time: 0, config: .default)

        #expect(result.luminance.min < 0.01)
        #expect(result.luminance.max > 0.99)
        #expect(abs(result.luminance.average - 0.5) < 0.02)
        #expect(result.luminance.percentile02 < 0.01)
        #expect(result.luminance.percentile98 > 0.99)
        #expect(result.exposureStatus == .clipped)
    }

    @Test func saturatedRed_reportsHighSaturation() {
        let red = makeImage(width: 256, height: 256) { _, _ in (220, 20, 20) }
        let result = analyzeFrame(cgImage: red, time: 0, config: .default)

        #expect(result.saturation > 0.7)
        #expect(result.histogram.red[220] > 0.9)
    }
}
