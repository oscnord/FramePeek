import Testing
@testable import FramePeekCore

/// The Planckian locus reference used for Duv/confidence was numerically wrong
/// (u off by ~20x at daylight temperatures), collapsing confidence to 0.1 for
/// virtually all content. These anchor the fixed Krystek approximation to
/// known illuminants.
struct CCTCalculatorTests {

    @Test func d65White_highConfidenceDaylightCCT() {
        let d65 = ChromaticityXY(x: 0.3127, y: 0.3290)
        let result = d65.calculateCCT()

        #expect(result != nil)
        if let result {
            #expect(result.cct > 6400 && result.cct < 6650)
            #expect(abs(result.duv) < 0.005)
            #expect(result.confidence >= 0.9)
        }
    }

    @Test func illuminantA_highConfidenceTungstenCCT() {
        let illuminantA = ChromaticityXY(x: 0.4476, y: 0.4074)
        let result = illuminantA.calculateCCT()

        #expect(result != nil)
        if let result {
            #expect(result.cct > 2750 && result.cct < 2950)
            #expect(abs(result.duv) < 0.005)
            #expect(result.confidence >= 0.9)
        }
    }

    @Test func neutralGrayRGB_resolvesToD65() {
        let result = calculateCCTFromRGB(r: 0.5, g: 0.5, b: 0.5, colorSpace: .bt709, contentType: .sdr)

        #expect(result != nil)
        if let result {
            #expect(result.cct > 6400 && result.cct < 6650)
            #expect(result.confidence >= 0.9)
        }
    }

    @Test func saturatedGreen_lowConfidence() {
        let green = ChromaticityXY(x: 0.30, y: 0.60)
        let result = green.calculateCCT()

        if let result {
            #expect(result.confidence <= 0.3)
            #expect(abs(result.duv) > 0.02)
        }
    }
}
