import Testing
import Foundation
@testable import FramePeekCore

/// EBU Tech 3341/3342 verification cases, synthesized rather than shipped as
/// audio files. Tolerances are the ones the EBU specifies for meters
/// (+/-0.1 LU for integrated loudness).
struct LoudnessMeterTests {

    private static let sampleRate = 48_000.0
    private static let chunkFrames = 4800

    /// Feeds a stereo sine at the given per-channel dBFS level, maintaining
    /// phase continuity across chunks
    private func feedSine(
        _ meter: LoudnessMeter,
        frequency: Double,
        levelDBFS: Double,
        seconds: Double,
        channelCount: Int = 2,
        phaseOffset: Double = 0
    ) {
        let amplitude = pow(10.0, levelDBFS / 20.0)
        let totalFrames = Int(seconds * Self.sampleRate)
        var frame = 0
        var buffer = [Float](repeating: 0, count: Self.chunkFrames * channelCount)

        while frame < totalFrames {
            let count = min(Self.chunkFrames, totalFrames - frame)
            for i in 0..<count {
                let t = Double(frame + i) / Self.sampleRate
                let value = Float(amplitude * sin(2.0 * .pi * frequency * t + phaseOffset))
                for ch in 0..<channelCount {
                    buffer[i * channelCount + ch] = value
                }
            }
            buffer.withUnsafeBufferPointer { buf in
                meter.process(
                    interleaved: UnsafeBufferPointer(start: buf.baseAddress!, count: count * channelCount),
                    frameCount: count
                )
            }
            frame += count
        }
    }

    // MARK: Tech 3341 integrated loudness

    @Test func tech3341Case1_minus23Sine_readsMinus23LUFS() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        feedSine(meter, frequency: 997, levelDBFS: -23, seconds: 20)
        let result = meter.finish()

        #expect(result.integratedLUFS != nil)
        if let integrated = result.integratedLUFS {
            #expect(abs(integrated - (-23.0)) <= 0.1)
        }
    }

    @Test func tech3341Case2_minus33Sine_readsMinus33LUFS() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        feedSine(meter, frequency: 997, levelDBFS: -33, seconds: 20)
        let result = meter.finish()

        if let integrated = result.integratedLUFS {
            #expect(abs(integrated - (-33.0)) <= 0.1)
        } else {
            Issue.record("expected an integrated loudness value")
        }
    }

    @Test func tech3341Case3_gatingExcludesQuietSections() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        feedSine(meter, frequency: 997, levelDBFS: -36, seconds: 10)
        feedSine(meter, frequency: 997, levelDBFS: -23, seconds: 60)
        feedSine(meter, frequency: 997, levelDBFS: -36, seconds: 10)
        let result = meter.finish()

        if let integrated = result.integratedLUFS {
            #expect(abs(integrated - (-23.0)) <= 0.1)
        } else {
            Issue.record("expected an integrated loudness value")
        }
    }

    @Test func silence_hasNoIntegratedLoudness() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        let silence = [Float](repeating: 0, count: Self.chunkFrames * 2)
        for _ in 0..<100 {
            silence.withUnsafeBufferPointer {
                meter.process(interleaved: $0, frameCount: Self.chunkFrames)
            }
        }
        let result = meter.finish()

        #expect(result.integratedLUFS == nil)
        #expect(result.truePeakDBTP == nil)
    }

    // MARK: True peak (BS.1770-4 Annex 2)

    @Test func truePeak_sineAtMinus6_readsMinus6DBTP() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 1)
        feedSine(meter, frequency: 997, levelDBFS: -6, seconds: 2, channelCount: 1)
        let result = meter.finish()

        if let peak = result.truePeakDBTP {
            #expect(abs(peak - (-6.0)) <= 0.3)
        } else {
            Issue.record("expected a true peak value")
        }
    }

    @Test func truePeak_detectsInterSamplePeaks() {
        // A sine at fs/4 with 45-degree phase never hits its true peak on a
        // sample: sampled peak reads ~3 dB low, oversampling must recover it
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 1)
        feedSine(
            meter,
            frequency: Self.sampleRate / 4.0,
            levelDBFS: -6.02,
            seconds: 2,
            channelCount: 1,
            phaseOffset: .pi / 4
        )
        let result = meter.finish()

        if let peak = result.truePeakDBTP {
            #expect(peak > -6.7, "oversampling must recover the inter-sample peak (sampled-only would read about -9 dB)")
            #expect(peak <= -5.7)
        } else {
            Issue.record("expected a true peak value")
        }
    }

    // MARK: Tech 3342 loudness range

    @Test func tech3342Case1_twoLevelTone_readsLRA10() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        feedSine(meter, frequency: 997, levelDBFS: -20, seconds: 20)
        feedSine(meter, frequency: 997, levelDBFS: -30, seconds: 20)
        let result = meter.finish()

        if let lra = result.loudnessRangeLU {
            #expect(abs(lra - 10.0) <= 1.0)
        } else {
            Issue.record("expected a loudness range value")
        }
    }

    // MARK: Short-term stream

    @Test func shortTermSamples_trackSignalLevel() {
        let meter = LoudnessMeter(sampleRate: Self.sampleRate, channelCount: 2)
        feedSine(meter, frequency: 997, levelDBFS: -23, seconds: 10)
        let samples = meter.drainNewShortTermSamples()

        #expect(samples.count > 50)  // 10 Hz cadence after the first 3 s window
        if let last = samples.last {
            #expect(abs(last.lufs - (-23.0)) <= 0.2)
            #expect(abs(last.time - 10.0) <= 0.2)
        }
        // Draining again yields nothing new
        #expect(meter.drainNewShortTermSamples().isEmpty)
    }

    // MARK: Coefficient sanity

    @Test func kWeighting48k_matchesSpecTable() {
        let c = LoudnessMeter.kWeightingCoefficients(sampleRate: 48_000)
        // BS.1770-4 tabulated values for 48 kHz
        #expect(abs(c[0] - 1.53512485958697) < 1e-6)   // shelf b0
        #expect(abs(c[3] - (-1.69065929318241)) < 1e-6) // shelf a1
        #expect(abs(c[4] - 0.73248077421585) < 1e-6)   // shelf a2
        #expect(abs(c[8] - (-1.99004745483398)) < 1e-6) // hp a1
        #expect(abs(c[9] - 0.99007225036621) < 1e-6)   // hp a2
    }
}
