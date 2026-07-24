import Foundation
import AVFoundation
import Accelerate
import CoreImage
import AppKit

// MARK: - Color Analyzer

/// Color analysis with proper CCT, luminance metrics, and scope generation
/// This replaces the simplified color analysis with broadcast-quality measurements

/// Performs comprehensive color analysis on video frames
/// - Parameters:
///   - asset: The AVAsset to analyze
///   - config: Analysis configuration (HDR type, resolution, etc.)
///   - sampleInterval: Interval in seconds between frame samples
///   - maxSamples: Maximum number of samples to analyze
/// - Returns: AsyncStream of progressive analysis updates
public func analyzeColor(
    asset: AVAsset,
    config: ColorAnalysisConfig = .default,
    sampleInterval: Double = 1.0,
    maxSamples: Int = 1000
) -> AsyncStream<ColorAnalysisUpdate> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            guard let videoTrack = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) else {
                continuation.yield(ColorAnalysisUpdate(samples: [], progress: 1.0, isFinished: true))
                continuation.finish()
                return
            }

            let duration = await AVAssetLoader.durationSeconds(of: asset)
            guard duration > 0 else {
                continuation.yield(ColorAnalysisUpdate(samples: [], progress: 1.0, isFinished: true))
                continuation.finish()
                return
            }
            
            // Detect color space from track metadata
            let colorSpace = await detectColorSpace(from: videoTrack)
            
            let effectiveInterval = sampleInterval > 0 ? sampleInterval : 1.0
            let estimatedSamples = min(maxSamples, Int(duration / effectiveInterval) + 1)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)
            generator.apertureMode = .productionAperture
            // Analysis downscales to 256x256; decode-time downscale instead of
            // decoding full 4K/8K frames (512 keeps headroom for wide aspect ratios)
            generator.maximumSize = CGSize(width: 512, height: 512)
            
            var samples: [FrameColorAnalysis] = []
            samples.reserveCapacity(estimatedSamples)

            var lastEmitTime: Double = -1

            // Decode stays sequential (hardware decoder), but per-frame pixel
            // analysis is CPU-bound and fans out to a bounded task group.
            // Results append in decode order via an index frontier.
            let analysisWidth = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2))

            await withTaskGroup(of: (Int, FrameColorAnalysis).self) { group in
                var pendingByIndex: [Int: FrameColorAnalysis] = [:]
                var nextToAppend = 0
                var decodedCount = 0
                var inFlight = 0
                var currentTime = 0.0

                func drainOne() async {
                    guard let (index, analysis) = await group.next() else { return }
                    inFlight -= 1
                    pendingByIndex[index] = analysis
                    while let next = pendingByIndex.removeValue(forKey: nextToAppend) {
                        samples.append(next)
                        nextToAppend += 1
                    }
                }

                while currentTime < duration && decodedCount < maxSamples {
                    if Task.isCancelled { break }

                    if inFlight >= analysisWidth {
                        await drainOne()

                        // Emit progress updates every 10 samples or 5 seconds of content
                        if let lastTime = samples.last?.time,
                           samples.count % 10 == 0 || lastTime - lastEmitTime >= 5.0 {
                            continuation.yield(ColorAnalysisUpdate(
                                samples: samples,
                                progress: min(1.0, currentTime / duration),
                                isFinished: false
                            ))
                            lastEmitTime = lastTime
                        }
                    }

                    let time = CMTime(seconds: currentTime, preferredTimescale: 600)

                    guard let cgImage = try? await generator.image(at: time).image else {
                        currentTime += effectiveInterval
                        continue
                    }

                    let index = decodedCount
                    let frameTime = currentTime
                    decodedCount += 1
                    inFlight += 1
                    group.addTask {
                        (index, analyzeFrame(
                            cgImage: cgImage,
                            time: frameTime,
                            config: config,
                            colorSpace: colorSpace
                        ))
                    }

                    currentTime += effectiveInterval
                }

                while inFlight > 0 {
                    await drainOne()
                }
            }

            // Final update
            continuation.yield(ColorAnalysisUpdate(
                samples: samples,
                progress: 1.0,
                isFinished: true
            ))
            continuation.finish()
        }
        
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Single Frame Analysis

/// Analyzes a single frame for all color metrics
public func analyzeFrame(
    cgImage: CGImage,
    time: Double,
    config: ColorAnalysisConfig,
    colorSpace: ColorSpace = .bt709
) -> FrameColorAnalysis {
    // Extract pixel data at analysis resolution
    let analysisWidth = 256
    let analysisHeight = 256
    let pixelCount = analysisWidth * analysisHeight
    let pixelData = extractPixelData(from: cgImage, width: analysisWidth, height: analysisHeight)

    // One interleaved-to-planar conversion feeds every metric below
    let rgb = planarRGB(from: pixelData, pixelCount: pixelCount)
    let luminancePlane = rec709LuminancePlane(rgb)

    let luminance = calculateLuminanceData(luminancePlane: luminancePlane)

    let histogram = calculateColorHistogramFromPixels(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight
    )

    let saturation = calculateAverageSaturation(rgb: rgb)

    // CCT calculation - may return nil for HDR content or highly saturated frames
    let cct: ColorTemperatureData?
    if config.hdrContentType == .sdr {
        cct = calculateFrameAverageCCT(
            rgb: rgb,
            luminancePlane: luminancePlane,
            colorSpace: colorSpace,
            contentType: config.hdrContentType
        )
    } else {
        // CCT is unreliable for tone-mapped HDR content
        cct = nil
    }

    // Generate waveform data if requested
    let waveform: WaveformData?
    if config.generateWaveform {
        waveform = generateWaveformData(
            luminancePlane: luminancePlane,
            width: analysisWidth,
            height: analysisHeight,
            resolution: config.waveformResolution
        )
    } else {
        waveform = nil
    }

    // Generate vectorscope data if requested
    let vectorscope: VectorscopeData?
    if config.generateVectorscope {
        vectorscope = generateVectorscopeData(
            rgb: rgb,
            pixelCount: pixelCount,
            resolution: config.vectorscopeResolution
        )
    } else {
        vectorscope = nil
    }

    // Determine exposure status
    let exposure = determineExposureStatus(luminance: luminance, histogram: histogram)

    return FrameColorAnalysis(
        time: time,
        luminance: luminance,
        colorTemperature: cct,
        saturation: saturation,
        histogram: histogram,
        waveformData: waveform,
        vectorscopeData: vectorscope,
        exposureStatus: exposure
    )
}

// MARK: - Planar Conversion

struct PlanarRGB {
    var r: [Float]
    var g: [Float]
    var b: [Float]
    var count: Int { r.count }
}

/// Deinterleaves RGBA8 into planar Float channels scaled to 0...1
func planarRGB(from pixelData: [UInt8], pixelCount: Int) -> PlanarRGB {
    var r = [Float](repeating: 0, count: pixelCount)
    var g = [Float](repeating: 0, count: pixelCount)
    var b = [Float](repeating: 0, count: pixelCount)

    pixelData.withUnsafeBufferPointer { buffer in
        let base = buffer.baseAddress!
        vDSP_vfltu8(base, 4, &r, 1, vDSP_Length(pixelCount))
        vDSP_vfltu8(base + 1, 4, &g, 1, vDSP_Length(pixelCount))
        vDSP_vfltu8(base + 2, 4, &b, 1, vDSP_Length(pixelCount))
    }

    var scale = Float(1.0 / 255.0)
    vDSP_vsmul(r, 1, &scale, &r, 1, vDSP_Length(pixelCount))
    vDSP_vsmul(g, 1, &scale, &g, 1, vDSP_Length(pixelCount))
    vDSP_vsmul(b, 1, &scale, &b, 1, vDSP_Length(pixelCount))

    return PlanarRGB(r: r, g: g, b: b)
}

/// Rec.709 luminance plane (appropriate for SDR and tone-mapped HDR)
func rec709LuminancePlane(_ rgb: PlanarRGB) -> [Float] {
    let n = vDSP_Length(rgb.count)
    var lum = [Float](repeating: 0, count: rgb.count)
    var cR: Float = 0.2126
    var cG: Float = 0.7152
    var cB: Float = 0.0722
    vDSP_vsmul(rgb.r, 1, &cR, &lum, 1, n)
    vDSP_vsma(rgb.g, 1, &cG, lum, 1, &lum, 1, n)
    vDSP_vsma(rgb.b, 1, &cB, lum, 1, &lum, 1, n)
    return lum
}

// MARK: - Pixel Data Extraction

private func extractPixelData(from cgImage: CGImage, width: Int, height: Int) -> [UInt8] {
    let bytesPerPixel = 4
    let pixelCount = width * height
    var pixelData = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
    
    guard let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return pixelData
    }
    
    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    return pixelData
}

// MARK: - Luminance Calculation

private func calculateLuminanceData(luminancePlane: [Float]) -> LuminanceData {
    let pixelCount = luminancePlane.count
    guard pixelCount > 0 else {
        return LuminanceData(min: 0, max: 1, average: 0, percentile98: 1, percentile02: 0)
    }
    let n = vDSP_Length(pixelCount)

    var minLum: Float = 0
    var maxLum: Float = 0
    var avgLum: Float = 0
    vDSP_minv(luminancePlane, 1, &minLum, n)
    vDSP_maxv(luminancePlane, 1, &maxLum, n)
    vDSP_meanv(luminancePlane, 1, &avgLum, n)

    // SIMD sort for exact percentiles
    var sorted = luminancePlane
    vDSP_vsort(&sorted, n, 1)

    let p02Index = Int(Double(pixelCount) * 0.02)
    let p98Index = Int(Double(pixelCount) * 0.98)
    let percentile02 = sorted[Swift.max(0, Swift.min(p02Index, pixelCount - 1))]
    let percentile98 = sorted[Swift.max(0, Swift.min(p98Index, pixelCount - 1))]

    return LuminanceData(
        min: Double(minLum),
        max: Double(maxLum),
        average: Double(avgLum),
        percentile98: Double(percentile98),
        percentile02: Double(percentile02)
    )
}

// MARK: - Histogram Calculation

private func calculateColorHistogramFromPixels(
    pixelData: [UInt8],
    width: Int,
    height: Int
) -> ColorHistogram {
    let pixelCount = width * height

    var redHist = [vImagePixelCount](repeating: 0, count: 256)
    var greenHist = [vImagePixelCount](repeating: 0, count: 256)
    var blueHist = [vImagePixelCount](repeating: 0, count: 256)
    var alphaHist = [vImagePixelCount](repeating: 0, count: 256)

    var mutablePixels = pixelData
    mutablePixels.withUnsafeMutableBytes { rawBuffer in
        var buffer = vImage_Buffer(
            data: rawBuffer.baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )
        // Channel order matches memory layout: R, G, B, X
        redHist.withUnsafeMutableBufferPointer { r in
            greenHist.withUnsafeMutableBufferPointer { g in
                blueHist.withUnsafeMutableBufferPointer { b in
                    alphaHist.withUnsafeMutableBufferPointer { a in
                        var histograms: [UnsafeMutablePointer<vImagePixelCount>?] = [
                            r.baseAddress, g.baseAddress, b.baseAddress, a.baseAddress
                        ]
                        histograms.withUnsafeMutableBufferPointer { histPtr in
                            _ = vImageHistogramCalculation_ARGB8888(
                                &buffer,
                                histPtr.baseAddress!,
                                vImage_Flags(kvImageNoFlags)
                            )
                        }
                    }
                }
            }
        }
    }

    let total = Double(pixelCount)
    return ColorHistogram(
        red: redHist.map { Double($0) / total },
        green: greenHist.map { Double($0) / total },
        blue: blueHist.map { Double($0) / total }
    )
}

// MARK: - Saturation Calculation

private func calculateAverageSaturation(rgb: PlanarRGB) -> Double {
    let pixelCount = rgb.count
    let n = vDSP_Length(pixelCount)

    // HSL max/min/delta planes via vDSP; the gated mean below stays scalar
    var maxC = [Float](repeating: 0, count: pixelCount)
    var minC = [Float](repeating: 0, count: pixelCount)
    vDSP_vmax(rgb.r, 1, rgb.g, 1, &maxC, 1, n)
    vDSP_vmax(maxC, 1, rgb.b, 1, &maxC, 1, n)
    vDSP_vmin(rgb.r, 1, rgb.g, 1, &minC, 1, n)
    vDSP_vmin(minC, 1, rgb.b, 1, &minC, 1, n)

    var totalSaturation: Float = 0
    var validPixels = 0

    for i in 0..<pixelCount {
        let delta = maxC[i] - minC[i]

        // Skip very dark pixels (saturation is unreliable)
        let lightness = (maxC[i] + minC[i]) / 2
        guard lightness > 0.05 && lightness < 0.95 else { continue }

        let saturation: Float
        if delta < 0.001 {
            saturation = 0  // Achromatic
        } else {
            saturation = delta / (1 - abs(2 * lightness - 1))
        }

        totalSaturation += Swift.min(1.0, saturation)  // Clamp to prevent >1.0 values
        validPixels += 1
    }

    return validPixels > 0 ? Double(totalSaturation) / Double(validPixels) : 0
}

// MARK: - Waveform Generation

/// Generates traditional broadcast-style waveform data
private func generateWaveformData(
    luminancePlane: [Float],
    width: Int,
    height: Int,
    resolution: Int
) -> WaveformData {
    let numColumns = resolution
    let numLevels = 256

    // Column index per source x, computed once instead of per pixel
    let columnForX: [Int] = (0..<width).map { x in
        let column = Int(Double(x) / Double(width) * Double(numColumns - 1))
        return Swift.max(0, Swift.min(column, numColumns - 1))
    }

    // Accumulate into one flat buffer; nested-array indexing per pixel is slow
    var flat = [Double](repeating: 0, count: numColumns * numLevels)
    let levelScale = Float(numLevels - 1)

    luminancePlane.withUnsafeBufferPointer { lum in
        flat.withUnsafeMutableBufferPointer { counts in
            for y in 0..<height {
                let rowStart = y * width
                for x in 0..<width {
                    let level = Int(lum[rowStart + x] * levelScale)
                    let clampedLevel = Swift.max(0, Swift.min(level, numLevels - 1))
                    counts[columnForX[x] * numLevels + clampedLevel] += 1
                }
            }
        }
    }

    var normalize = 1.0 / Double(height)
    vDSP_vsmulD(flat, 1, &normalize, &flat, 1, vDSP_Length(flat.count))

    let columns: [[Double]] = (0..<numColumns).map { col in
        Array(flat[(col * numLevels)..<((col + 1) * numLevels)])
    }

    return WaveformData(columns: columns, channelMode: .luma)
}

// MARK: - Vectorscope Generation

/// Generates vectorscope data showing color distribution
private func generateVectorscopeData(
    rgb: PlanarRGB,
    pixelCount: Int,
    resolution: Int
) -> VectorscopeData {
    // Sample pixels (use every Nth pixel for performance)
    let sampleStep = Swift.max(1, pixelCount / 10000)

    var points: [VectorscopePoint] = []

    for i in stride(from: 0, to: pixelCount, by: sampleStep) {
        let r = Double(rgb.r[i])
        let g = Double(rgb.g[i])
        let b = Double(rgb.b[i])

        // Convert RGB to YUV (BT.709)
        // Y = 0.2126*R + 0.7152*G + 0.0722*B
        // U = -0.09991*R - 0.33609*G + 0.436*B  (Cb - 0.5)
        // V = 0.615*R - 0.55861*G - 0.05639*B   (Cr - 0.5)
        
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let u = -0.09991 * r - 0.33609 * g + 0.436 * b
        let v = 0.615 * r - 0.55861 * g - 0.05639 * b
        
        // Skip very dark or very bright pixels (unreliable chroma)
        guard y > 0.05 && y < 0.95 else { continue }
        
        // Normalize U and V to -0.5 to 0.5 range
        // Standard UV range is approximately -0.436 to 0.436 for U, -0.615 to 0.615 for V
        let normalizedU = u / 0.436 * 0.5
        let normalizedV = v / 0.615 * 0.5
        
        // Clamp to valid range
        let clampedU = Swift.max(-0.5, Swift.min(0.5, normalizedU))
        let clampedV = Swift.max(-0.5, Swift.min(0.5, normalizedV))
        
        points.append(VectorscopePoint(u: clampedU, v: clampedV, intensity: 1.0))
    }
    
    return VectorscopeData(points: points, gridSize: resolution)
}

// MARK: - Exposure Status Determination

private func determineExposureStatus(luminance: LuminanceData, histogram: ColorHistogram) -> ExposureStatus {
    // Check for clipping
    let highlightClip = histogram.red[255] + histogram.green[255] + histogram.blue[255]
    let shadowClip = histogram.red[0] + histogram.green[0] + histogram.blue[0]
    
    if highlightClip > 0.1 || shadowClip > 0.1 {
        return .clipped
    }
    
    // Check dynamic range
    let dynamicRange = luminance.percentile98 - luminance.percentile02
    if dynamicRange > 0.8 {
        return .highDynamicRange
    }
    
    // Check exposure based on average luminance
    let avg = luminance.average
    
    if avg < 0.15 {
        return .underexposed
    } else if avg < 0.35 {
        return .slightlyUnder
    } else if avg < 0.65 {
        return .properlyExposed
    } else if avg < 0.80 {
        return .slightlyOver
    } else {
        return .overexposed
    }
}

// MARK: - Color Space Detection

private func detectColorSpace(from track: AVAssetTrack) async -> ColorSpace {
    do {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] else {
            return .bt709
        }
        
        if let primaries = extDict[kCMFormatDescriptionExtension_ColorPrimaries] as? String {
            return ColorSpace.from(colorPrimaries: primaries)
        }
    } catch {
        // Default to BT.709
    }
    
    return .bt709
}

// MARK: - Legacy Compatibility

/// Converts frame analysis to legacy ColorSample format
/// This maintains backward compatibility with existing UI components
public func convertToLegacyColorSample(_ analysis: FrameColorAnalysis) -> ColorSample {
    return ColorSample(
        time: analysis.time,
        brightness: analysis.luminance.average,
        colorTemperature: analysis.colorTemperature?.cct,
        histogram: analysis.histogram
    )
}

/// Converts frame analyses to legacy format
public func convertToLegacyColorSamples(_ analyses: [FrameColorAnalysis]) -> [ColorSample] {
    return analyses.map { convertToLegacyColorSample($0) }
}
