import Foundation
import AVFoundation
import CoreImage
import AppKit

// MARK: - Professional Color Analyzer

/// Professional color analysis with proper CCT, luminance metrics, and scope generation
/// This replaces the simplified color analysis with broadcast-quality measurements

/// Performs comprehensive color analysis on video frames
/// - Parameters:
///   - asset: The AVAsset to analyze
///   - config: Analysis configuration (HDR type, resolution, etc.)
///   - sampleInterval: Interval in seconds between frame samples
///   - maxSamples: Maximum number of samples to analyze
/// - Returns: AsyncStream of progressive analysis updates
public func analyzeColorProfessional(
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
            
            var samples: [FrameColorAnalysis] = []
            samples.reserveCapacity(estimatedSamples)
            
            var currentTime = 0.0
            var sampleCount = 0
            var lastEmitTime: Double = -1
            
            while currentTime < duration && sampleCount < maxSamples {
                if Task.isCancelled { break }
                
                let time = CMTime(seconds: currentTime, preferredTimescale: 600)
                
                guard let cgImage = try? await generator.image(at: time).image else {
                    currentTime += effectiveInterval
                    continue
                }
                
                // Analyze the frame
                let analysis = analyzeFrame(
                    cgImage: cgImage,
                    time: currentTime,
                    config: config,
                    colorSpace: colorSpace
                )
                
                samples.append(analysis)
                sampleCount += 1
                
                // Emit progress updates every 10 samples or 5 seconds of content
                let shouldEmit = sampleCount % 10 == 0 || currentTime - lastEmitTime >= 5.0
                if shouldEmit {
                    let progress = min(1.0, currentTime / duration)
                    continuation.yield(ColorAnalysisUpdate(
                        samples: samples,
                        progress: progress,
                        isFinished: false
                    ))
                    lastEmitTime = currentTime
                }
                
                currentTime += effectiveInterval
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
    let pixelData = extractPixelData(from: cgImage, width: analysisWidth, height: analysisHeight)
    
    // Calculate all metrics
    let luminance = calculateLuminanceData(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight,
        contentType: config.hdrContentType
    )
    
    let histogram = calculateColorHistogramFromPixels(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight
    )
    
    let saturation = calculateAverageSaturation(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight
    )
    
    // CCT calculation - may return nil for HDR content or highly saturated frames
    let cct: ColorTemperatureData?
    if config.hdrContentType == .sdr {
        cct = calculateFrameAverageCCT(
            pixelData: pixelData,
            width: analysisWidth,
            height: analysisHeight,
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
            pixelData: pixelData,
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
            pixelData: pixelData,
            width: analysisWidth,
            height: analysisHeight,
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

private func calculateLuminanceData(
    pixelData: [UInt8],
    width: Int,
    height: Int,
    contentType: HDRContentType
) -> LuminanceData {
    let pixelCount = width * height
    let bytesPerPixel = 4
    
    var luminanceValues: [Double] = []
    luminanceValues.reserveCapacity(pixelCount)
    
    for i in 0..<pixelCount {
        let offset = i * bytesPerPixel
        let r = Double(pixelData[offset]) / 255.0
        let g = Double(pixelData[offset + 1]) / 255.0
        let b = Double(pixelData[offset + 2]) / 255.0
        
        // Use Rec.709 luminance coefficients (appropriate for SDR and tone-mapped HDR)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        luminanceValues.append(luminance)
    }
    
    // Sort for percentile calculations
    let sorted = luminanceValues.sorted()
    
    let minLum = sorted.first ?? 0
    let maxLum = sorted.last ?? 1
    let avgLum = luminanceValues.reduce(0, +) / Double(pixelCount)
    
    // Percentiles
    let p02Index = Int(Double(pixelCount) * 0.02)
    let p98Index = Int(Double(pixelCount) * 0.98)
    let percentile02 = sorted[Swift.max(0, Swift.min(p02Index, pixelCount - 1))]
    let percentile98 = sorted[Swift.max(0, Swift.min(p98Index, pixelCount - 1))]
    
    return LuminanceData(
        min: minLum,
        max: maxLum,
        average: avgLum,
        percentile98: percentile98,
        percentile02: percentile02
    )
}

// MARK: - Histogram Calculation

private func calculateColorHistogramFromPixels(
    pixelData: [UInt8],
    width: Int,
    height: Int
) -> ColorHistogram {
    let pixelCount = width * height
    let bytesPerPixel = 4
    
    var redHist = [Int](repeating: 0, count: 256)
    var greenHist = [Int](repeating: 0, count: 256)
    var blueHist = [Int](repeating: 0, count: 256)
    
    for i in 0..<pixelCount {
        let offset = i * bytesPerPixel
        let r = Int(pixelData[offset])
        let g = Int(pixelData[offset + 1])
        let b = Int(pixelData[offset + 2])
        
        redHist[r] += 1
        greenHist[g] += 1
        blueHist[b] += 1
    }
    
    let total = Double(pixelCount)
    return ColorHistogram(
        red: redHist.map { Double($0) / total },
        green: greenHist.map { Double($0) / total },
        blue: blueHist.map { Double($0) / total }
    )
}

// MARK: - Saturation Calculation

private func calculateAverageSaturation(
    pixelData: [UInt8],
    width: Int,
    height: Int
) -> Double {
    let pixelCount = width * height
    let bytesPerPixel = 4
    
    var totalSaturation: Double = 0
    var validPixels = 0
    
    for i in 0..<pixelCount {
        let offset = i * bytesPerPixel
        let r = Double(pixelData[offset]) / 255.0
        let g = Double(pixelData[offset + 1]) / 255.0
        let b = Double(pixelData[offset + 2]) / 255.0
        
        // Calculate saturation using HSL model
        let maxC = Swift.max(r, Swift.max(g, b))
        let minC = Swift.min(r, Swift.min(g, b))
        let delta = maxC - minC
        
        // Skip very dark pixels (saturation is unreliable)
        let lightness = (maxC + minC) / 2
        guard lightness > 0.05 && lightness < 0.95 else { continue }
        
        let saturation: Double
        if delta < 0.001 {
            saturation = 0  // Achromatic
        } else {
            saturation = delta / (1 - abs(2 * lightness - 1))
        }
        
        totalSaturation += Swift.min(1.0, saturation)  // Clamp to prevent >1.0 values
        validPixels += 1
    }
    
    return validPixels > 0 ? totalSaturation / Double(validPixels) : 0
}

// MARK: - Waveform Generation

/// Generates traditional broadcast-style waveform data
private func generateWaveformData(
    pixelData: [UInt8],
    width: Int,
    height: Int,
    resolution: Int
) -> WaveformData {
    let bytesPerPixel = 4
    let numColumns = resolution
    let numLevels = 256
    
    // Initialize columns (each column is a histogram of luminance at that x position)
    var columns = [[Double]](repeating: [Double](repeating: 0, count: numLevels), count: numColumns)
    
    // Map source x coordinates to waveform columns
    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * width + x
            let offset = pixelIndex * bytesPerPixel
            
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            
            // Calculate luminance
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            
            // Map to column and level
            let column = Int(Double(x) / Double(width) * Double(numColumns - 1))
            let level = Int(luminance * Double(numLevels - 1))
            
            let clampedColumn = Swift.max(0, Swift.min(column, numColumns - 1))
            let clampedLevel = Swift.max(0, Swift.min(level, numLevels - 1))
            
            columns[clampedColumn][clampedLevel] += 1
        }
    }
    
    // Normalize each column
    let pixelsPerColumn = Double(height)
    for col in 0..<numColumns {
        for level in 0..<numLevels {
            columns[col][level] /= pixelsPerColumn
        }
    }
    
    return WaveformData(columns: columns, channelMode: .luma)
}

// MARK: - Vectorscope Generation

/// Generates vectorscope data showing color distribution
private func generateVectorscopeData(
    pixelData: [UInt8],
    width: Int,
    height: Int,
    resolution: Int
) -> VectorscopeData {
    let bytesPerPixel = 4
    let pixelCount = width * height
    
    // Sample pixels (use every Nth pixel for performance)
    let sampleStep = Swift.max(1, pixelCount / 10000)
    
    var points: [VectorscopePoint] = []
    
    for i in stride(from: 0, to: pixelCount, by: sampleStep) {
        let offset = i * bytesPerPixel
        let r = Double(pixelData[offset]) / 255.0
        let g = Double(pixelData[offset + 1]) / 255.0
        let b = Double(pixelData[offset + 2]) / 255.0
        
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

/// Converts professional analysis to legacy ColorSample format
/// This maintains backward compatibility with existing UI components
public func convertToLegacyColorSample(_ analysis: FrameColorAnalysis) -> ColorSample {
    return ColorSample(
        time: analysis.time,
        brightness: analysis.luminance.average,
        colorTemperature: analysis.colorTemperature?.cct,
        histogram: analysis.histogram
    )
}

/// Converts array of professional analyses to legacy format
public func convertToLegacyColorSamples(_ analyses: [FrameColorAnalysis]) -> [ColorSample] {
    return analyses.map { convertToLegacyColorSample($0) }
}

// MARK: - Single Frame Analysis for Player Overlay

/// Analyzes a single frame for real-time display in player overlay
/// Optimized for speed with reduced resolution
public func analyzeFrameForOverlay(
    cgImage: CGImage,
    config: ColorAnalysisConfig = .default
) -> FrameColorAnalysis {
    // Use lower resolution for real-time analysis
    let analysisWidth = 128
    let analysisHeight = 128
    let pixelData = extractPixelData(from: cgImage, width: analysisWidth, height: analysisHeight)
    
    let luminance = calculateLuminanceData(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight,
        contentType: config.hdrContentType
    )
    
    let histogram = calculateColorHistogramFromPixels(
        pixelData: pixelData,
        width: analysisWidth,
        height: analysisHeight
    )
    
    let exposure = determineExposureStatus(luminance: luminance, histogram: histogram)
    
    // Skip expensive calculations for overlay
    return FrameColorAnalysis(
        time: 0,
        luminance: luminance,
        colorTemperature: nil,
        saturation: 0,
        histogram: histogram,
        waveformData: nil,
        vectorscopeData: nil,
        exposureStatus: exposure
    )
}
