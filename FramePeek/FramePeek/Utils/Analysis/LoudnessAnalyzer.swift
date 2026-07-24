import Foundation
import AVFoundation
import Accelerate

// MARK: - Loudness Meter (ITU-R BS.1770-4 / EBU R128)

/// Streaming loudness meter. Feed interleaved Float32 PCM via process(),
/// read progressive short-term values, then finish() for the gated result.
/// Pure DSP with no AVFoundation dependency so tests can drive it with
/// synthesized signals (EBU Tech 3341/3342 cases).
public final class LoudnessMeter {

    public let sampleRate: Double
    public let channelCount: Int

    private let channelWeights: [Double]
    private let hopSamples: Int                 // 100 ms
    private static let momentaryHops = 4        // 400 ms window
    private static let shortTermHops = 30       // 3 s window
    private static let absoluteGateLUFS = -70.0

    private let biquadSetup: vDSP_biquad_Setup
    private var biquadDelays: [[Float]]         // per channel, 2*sections + 2

    // Per-channel accumulation for the current 100 ms hop
    private var hopFill = 0
    private var hopEnergy: [Double]             // running sum of squares per channel
    private var hopEnergies: [[Double]] = []    // completed hops, per channel

    private var shortTermComputed = 0
    private var totalFrames = 0

    // True peak state: 4x oversampling via zero-stuff + lowpass FIR
    private static let oversample = 4
    private static let firTaps = 48
    private let firFilter: [Float]
    private var peakHistory: [[Float]]          // per channel, last (firTaps-1) stuffed samples
    private var maxTruePeak: Float = 0
    private var maxSamplePeak: Float = 0

    // Scratch buffers reused across process() calls
    private var channelScratch: [Float] = []
    private var weightedScratch: [Float] = []
    private var stuffedScratch: [Float] = []
    private var convScratch: [Float] = []

    public init(sampleRate: Double, channelCount: Int) {
        precondition(sampleRate > 0 && channelCount > 0)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.channelWeights = Self.weights(forChannelCount: channelCount)
        self.hopSamples = Int((sampleRate / 10.0).rounded())
        self.hopEnergy = [Double](repeating: 0, count: channelCount)

        let coefficients = Self.kWeightingCoefficients(sampleRate: sampleRate)
        self.biquadSetup = vDSP_biquad_CreateSetup(coefficients, 2)!
        self.biquadDelays = (0..<channelCount).map { _ in [Float](repeating: 0, count: 2 * 2 + 2) }

        self.firFilter = Self.upsamplingFilter(taps: Self.firTaps, factor: Self.oversample)
        self.peakHistory = (0..<channelCount).map { _ in [Float](repeating: 0, count: Self.firTaps - 1) }
    }

    deinit {
        vDSP_biquad_DestroySetup(biquadSetup)
    }

    // MARK: Coefficients

    /// BS.1770-4 K-weighting: high shelf followed by high-pass. The spec
    /// tabulates 48 kHz coefficients; this derives them from the analog
    /// prototype so any sample rate works (matches the published table at 48k).
    static func kWeightingCoefficients(sampleRate: Double) -> [Double] {
        // Stage 1: spherical-head high shelf
        let f0 = 1681.974450955533
        let gainDB = 3.999843853973347
        let q1 = 0.7071752369554196

        let k1 = tan(.pi * f0 / sampleRate)
        let vh = pow(10.0, gainDB / 20.0)
        let vb = pow(vh, 0.4996667741545416)
        let a0s = 1.0 + k1 / q1 + k1 * k1

        let shelfB0 = (vh + vb * k1 / q1 + k1 * k1) / a0s
        let shelfB1 = 2.0 * (k1 * k1 - vh) / a0s
        let shelfB2 = (vh - vb * k1 / q1 + k1 * k1) / a0s
        let shelfA1 = 2.0 * (k1 * k1 - 1.0) / a0s
        let shelfA2 = (1.0 - k1 / q1 + k1 * k1) / a0s

        // Stage 2: 38 Hz high-pass (RLB weighting)
        let f2 = 38.13547087602444
        let q2 = 0.5003270373238773
        let k2 = tan(.pi * f2 / sampleRate)
        let a0h = 1.0 + k2 / q2 + k2 * k2

        let hpA1 = 2.0 * (k2 * k2 - 1.0) / a0h
        let hpA2 = (1.0 - k2 / q2 + k2 * k2) / a0h

        // vDSP_biquad layout: b0 b1 b2 a1 a2 per section
        return [
            shelfB0, shelfB1, shelfB2, shelfA1, shelfA2,
            1.0, -2.0, 1.0, hpA1, hpA2,
        ]
    }

    static func weights(forChannelCount count: Int) -> [Double] {
        // BS.1770-4: L/R/C weigh 1.0, surrounds 1.41, LFE excluded.
        // Standard 5.1 order is L R C LFE Ls Rs; other layouts weigh 1.0
        // since the channel order cannot be assumed.
        if count == 6 {
            return [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]
        }
        return [Double](repeating: 1.0, count: count)
    }

    /// Windowed-sinc lowpass at the original Nyquist for 4x zero-stuffed
    /// upsampling, gain-compensated for the stuffing
    static func upsamplingFilter(taps: Int, factor: Int) -> [Float] {
        let center = Double(taps - 1) / 2.0
        let cutoff = 1.0 / (2.0 * Double(factor))
        var filter = [Float](repeating: 0, count: taps)
        for n in 0..<taps {
            let x = Double(n) - center
            let sinc = x == 0 ? 2.0 * cutoff : sin(2.0 * .pi * cutoff * x) / (.pi * x)
            // Blackman window
            let w = 0.42
                - 0.5 * cos(2.0 * .pi * Double(n) / Double(taps - 1))
                + 0.08 * cos(4.0 * .pi * Double(n) / Double(taps - 1))
            filter[n] = Float(sinc * w * Double(factor))
        }
        return filter
    }

    // MARK: Processing

    public func process(interleaved: UnsafeBufferPointer<Float>, frameCount: Int) {
        guard frameCount > 0, interleaved.count >= frameCount * channelCount else { return }

        if channelScratch.count < frameCount {
            channelScratch = [Float](repeating: 0, count: frameCount)
            weightedScratch = [Float](repeating: 0, count: frameCount)
        }

        for channel in 0..<channelCount {
            // Deinterleave via strided add-zero
            var zero: Float = 0
            vDSP_vsadd(
                interleaved.baseAddress! + channel, vDSP_Stride(channelCount),
                &zero, &channelScratch, 1, vDSP_Length(frameCount)
            )

            trackTruePeak(channel: channel, samples: channelScratch, count: frameCount)

            // K-weighting
            biquadDelays[channel].withUnsafeMutableBufferPointer { delays in
                vDSP_biquad(
                    biquadSetup, delays.baseAddress!,
                    channelScratch, 1, &weightedScratch, 1, vDSP_Length(frameCount)
                )
            }

            accumulateHops(channel: channel, weighted: weightedScratch, count: frameCount)
        }

        hopFill = (hopFill + frameCount) % hopSamples
        totalFrames += frameCount

        // accumulateHops completed hop rows channel by channel; normalize the
        // bookkeeping now that every channel has been folded in
        finalizePendingHops()
    }

    private var pendingHopRows: [[Double]] = []

    private func accumulateHops(channel: Int, weighted: [Float], count: Int) {
        var offset = 0
        var fill = hopFill
        var rowIndex = 0

        while offset < count {
            let take = min(hopSamples - fill, count - offset)
            var sumsq: Float = 0
            weighted.withUnsafeBufferPointer { buf in
                vDSP_svesq(buf.baseAddress! + offset, 1, &sumsq, vDSP_Length(take))
            }
            hopEnergy[channel] += Double(sumsq)
            fill += take
            offset += take

            if fill == hopSamples {
                if rowIndex >= pendingHopRows.count {
                    pendingHopRows.append([Double](repeating: 0, count: channelCount))
                }
                pendingHopRows[rowIndex][channel] = hopEnergy[channel]
                hopEnergy[channel] = 0
                rowIndex += 1
                fill = 0
            }
        }
    }

    private func finalizePendingHops() {
        if !pendingHopRows.isEmpty {
            hopEnergies.append(contentsOf: pendingHopRows)
            pendingHopRows.removeAll(keepingCapacity: true)
        }
    }

    private func trackTruePeak(channel: Int, samples: [Float], count: Int) {
        var samplePeak: Float = 0
        samples.withUnsafeBufferPointer { buf in
            vDSP_maxmgv(buf.baseAddress!, 1, &samplePeak, vDSP_Length(count))
        }
        maxSamplePeak = max(maxSamplePeak, samplePeak)

        // Zero-stuff by 4, prepend filter history, lowpass, take max magnitude
        let stuffedCount = count * Self.oversample
        let historyCount = Self.firTaps - 1
        let paddedCount = historyCount + stuffedCount

        if stuffedScratch.count < paddedCount {
            stuffedScratch = [Float](repeating: 0, count: paddedCount)
            convScratch = [Float](repeating: 0, count: stuffedCount)
        }

        stuffedScratch.withUnsafeMutableBufferPointer { stuffed in
            peakHistory[channel].withUnsafeBufferPointer { history in
                stuffed.baseAddress!.update(from: history.baseAddress!, count: historyCount)
            }
            vDSP_vclr(stuffed.baseAddress! + historyCount, 1, vDSP_Length(stuffedCount))
            samples.withUnsafeBufferPointer { input in
                var zero: Float = 0
                vDSP_vsadd(
                    input.baseAddress!, 1,
                    &zero,
                    stuffed.baseAddress! + historyCount, vDSP_Stride(Self.oversample),
                    vDSP_Length(count)
                )
            }

            firFilter.withUnsafeBufferPointer { filter in
                convScratch.withUnsafeMutableBufferPointer { out in
                    vDSP_conv(
                        stuffed.baseAddress!, 1,
                        filter.baseAddress! + Self.firTaps - 1, -1,
                        out.baseAddress!, 1,
                        vDSP_Length(stuffedCount), vDSP_Length(Self.firTaps)
                    )
                    var peak: Float = 0
                    vDSP_maxmgv(out.baseAddress!, 1, &peak, vDSP_Length(stuffedCount))
                    maxTruePeak = max(maxTruePeak, peak)
                }
            }

            // Carry the tail as history for the next chunk
            peakHistory[channel].withUnsafeMutableBufferPointer { history in
                history.baseAddress!.update(
                    from: stuffed.baseAddress! + paddedCount - historyCount,
                    count: historyCount
                )
            }
        }
    }

    // MARK: Readouts

    private func blockLoudness(_ weightedMeanSquare: Double) -> Double {
        -0.691 + 10.0 * log10(weightedMeanSquare)
    }

    /// Weighted mean square over a window of hop rows [start, start+length)
    private func windowMeanSquare(start: Int, length: Int) -> Double {
        let windowSamples = Double(length * hopSamples)
        var total = 0.0
        for channel in 0..<channelCount where channelWeights[channel] > 0 {
            var energy = 0.0
            for row in start..<(start + length) {
                energy += hopEnergies[row][channel]
            }
            total += channelWeights[channel] * (energy / windowSamples)
        }
        return total
    }

    /// Number of complete short-term (3 s) windows available so far
    public var shortTermWindowCount: Int {
        max(0, hopEnergies.count - Self.shortTermHops + 1)
    }

    /// Returns short-term samples not yet drained (for progressive UI updates)
    public func drainNewShortTermSamples() -> [LoudnessSample] {
        let available = shortTermWindowCount
        guard available > shortTermComputed else { return [] }

        var samples: [LoudnessSample] = []
        samples.reserveCapacity(available - shortTermComputed)
        for index in shortTermComputed..<available {
            let meanSquare = windowMeanSquare(start: index, length: Self.shortTermHops)
            guard meanSquare > 0 else { continue }
            let time = Double(index + Self.shortTermHops) * Double(hopSamples) / sampleRate
            samples.append(LoudnessSample(time: time, lufs: blockLoudness(meanSquare)))
        }
        shortTermComputed = available
        return samples
    }

    public func finish() -> LoudnessResult {
        finalizePendingHops()

        // Momentary blocks: 400 ms window sliding by one hop
        var momentaryMeanSquares: [Double] = []
        if hopEnergies.count >= Self.momentaryHops {
            momentaryMeanSquares.reserveCapacity(hopEnergies.count - Self.momentaryHops + 1)
            for start in 0...(hopEnergies.count - Self.momentaryHops) {
                momentaryMeanSquares.append(windowMeanSquare(start: start, length: Self.momentaryHops))
            }
        }

        // Integrated: absolute gate at -70 LUFS, then relative gate 10 LU
        // below the loudness of the absolutely-gated mean
        var integrated: Double?
        let absoluteGated = momentaryMeanSquares.filter {
            $0 > 0 && blockLoudness($0) > Self.absoluteGateLUFS
        }
        if !absoluteGated.isEmpty {
            let absoluteMean = absoluteGated.reduce(0, +) / Double(absoluteGated.count)
            let relativeGate = blockLoudness(absoluteMean) - 10.0
            let relativeGated = absoluteGated.filter { blockLoudness($0) > relativeGate }
            if !relativeGated.isEmpty {
                let mean = relativeGated.reduce(0, +) / Double(relativeGated.count)
                integrated = blockLoudness(mean)
            }
        }

        // Short-term series for LRA (EBU Tech 3342: -70 absolute gate, then
        // -20 LU relative gate, LRA = P95 - P10)
        var shortTermMeanSquares: [Double] = []
        if hopEnergies.count >= Self.shortTermHops {
            shortTermMeanSquares.reserveCapacity(hopEnergies.count - Self.shortTermHops + 1)
            for start in 0...(hopEnergies.count - Self.shortTermHops) {
                shortTermMeanSquares.append(windowMeanSquare(start: start, length: Self.shortTermHops))
            }
        }

        var loudnessRange: Double?
        let lraAbsoluteGated = shortTermMeanSquares.filter {
            $0 > 0 && blockLoudness($0) > Self.absoluteGateLUFS
        }
        if lraAbsoluteGated.count >= 2 {
            let mean = lraAbsoluteGated.reduce(0, +) / Double(lraAbsoluteGated.count)
            let gate = blockLoudness(mean) - 20.0
            let gated = lraAbsoluteGated.map(blockLoudness).filter { $0 > gate }.sorted()
            if gated.count >= 2 {
                loudnessRange = percentile(gated, 0.95) - percentile(gated, 0.10)
            }
        }

        let maxMomentary = momentaryMeanSquares.filter { $0 > 0 }.max().map(blockLoudness)
        let maxShortTerm = shortTermMeanSquares.filter { $0 > 0 }.max().map(blockLoudness)

        // The FIR can slightly undershoot the sampled peak; report whichever is higher
        let peak = max(maxTruePeak, maxSamplePeak)
        let truePeakDBTP: Double? = peak > 0 ? 20.0 * log10(Double(peak)) : nil

        return LoudnessResult(
            integratedLUFS: integrated,
            loudnessRangeLU: loudnessRange,
            truePeakDBTP: truePeakDBTP,
            maxMomentaryLUFS: maxMomentary,
            maxShortTermLUFS: maxShortTerm,
            channelCount: channelCount,
            sampleRate: sampleRate
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }
}

// MARK: - Asset Extraction

/// Measures loudness of one audio track, yielding progressive short-term
/// samples and the final gated result
public func analyzeLoudness(
    asset: AVAsset,
    audioTrack: AVAssetTrack
) -> AsyncStream<LoudnessUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            let finish = LoudnessUpdate(appendedShortTermSamples: [], result: nil)

            guard let reader = try? AVAssetReader(asset: asset) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]

            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else {
                continuation.yield(finish)
                continuation.finish()
                return
            }
            reader.add(output)

            guard reader.startReading() else {
                continuation.yield(finish)
                continuation.finish()
                return
            }

            var meter: LoudnessMeter?
            var lastYield = Date.now

            while !Task.isCancelled {
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    if reader.status != .reading { break }
                    continue
                }

                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
                      let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
                else { continue }

                if meter == nil {
                    meter = LoudnessMeter(
                        sampleRate: asbd.mSampleRate,
                        channelCount: Int(asbd.mChannelsPerFrame)
                    )
                }
                guard let meter else { continue }

                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer, atOffset: 0,
                    lengthAtOffsetOut: nil, totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )
                guard status == noErr, let data = dataPointer, length > 0 else { continue }

                let floatCount = length / MemoryLayout<Float>.size
                let frameCount = floatCount / meter.channelCount
                guard frameCount > 0 else { continue }

                data.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                    meter.process(
                        interleaved: UnsafeBufferPointer(start: floats, count: floatCount),
                        frameCount: frameCount
                    )
                }

                let now = Date.now
                if now.timeIntervalSince(lastYield) >= 0.25 {
                    let fresh = meter.drainNewShortTermSamples()
                    if !fresh.isEmpty {
                        continuation.yield(LoudnessUpdate(appendedShortTermSamples: fresh, result: nil))
                    }
                    lastYield = now
                }
            }

            if reader.status == .reading {
                reader.cancelReading()
            }

            if let meter, !Task.isCancelled {
                let fresh = meter.drainNewShortTermSamples()
                continuation.yield(LoudnessUpdate(appendedShortTermSamples: fresh, result: meter.finish()))
            } else {
                continuation.yield(finish)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}
