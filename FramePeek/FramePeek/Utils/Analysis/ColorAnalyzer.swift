import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Analyzes color properties of video frames over time
/// - Parameters:
///   - asset: The AVAsset to analyze
///   - sampleInterval: Interval in seconds between frame samples (default: 1.0, must be > 0)
///   - maxSamples: Maximum number of samples to return
///   - smoothingFactor: Smoothing factor for brightness and temperature (default: 0.3)
/// - Returns: AsyncStream of color samples
func analyzeColor(
    asset: AVAsset,
    sampleInterval: Double = 1.0,
    maxSamples: Int = 1000,
    smoothingFactor: Double = 0.3
) -> AsyncStream<[ColorSample]> {
    AsyncStream { continuation in
        let task = Task.detached(priority: .userInitiated) {
            guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else {
                continuation.finish()
                return
            }

            let duration = (try? await asset.load(.duration).seconds) ?? 0
            guard duration > 0 else {
                continuation.finish()
                return
            }

            // Validate sampleInterval to prevent infinite loop or division issues
            let effectiveSampleInterval = sampleInterval > 0 ? sampleInterval : 1.0

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)
            generator.apertureMode = .productionAperture

            var colorSamples: [ColorSample] = []
            colorSamples.reserveCapacity(min(maxSamples, Int(duration / effectiveSampleInterval) + 1))
            var currentTime = 0.0
            var sampleCount = 0
            var lastEmittedTime: Double = 0

            var previousBrightness: Double?
            var previousTemperature: Double?
            let effectiveSmoothingFactor = max(0.0, min(1.0, smoothingFactor))

            while currentTime < duration && sampleCount < maxSamples {
                if Task.isCancelled { break }

                let time = CMTime(seconds: currentTime, preferredTimescale: 600)

                guard let cgImage = try? await generator.image(at: time).image else {
                currentTime += effectiveSampleInterval
                    continue
                }

                let rawBrightness = calculateBrightness(cgImage: cgImage)
                let histogram = calculateColorHistogram(cgImage: cgImage)
                let rawTemperature = estimateColorTemperature(histogram: histogram)

                let smoothedBrightness: Double
                if let prev = previousBrightness {
                    smoothedBrightness = prev * (1 - effectiveSmoothingFactor) + rawBrightness * effectiveSmoothingFactor
                } else {
                    smoothedBrightness = rawBrightness
                }
                previousBrightness = smoothedBrightness

                let smoothedTemperature: Double?
                if let rawTemp = rawTemperature {
                    if let prev = previousTemperature {
                        smoothedTemperature = prev * (1 - effectiveSmoothingFactor) + rawTemp * effectiveSmoothingFactor
                    } else {
                        smoothedTemperature = rawTemp
                    }
                    previousTemperature = smoothedTemperature
                } else {
                    smoothedTemperature = previousTemperature
                }

                colorSamples.append(ColorSample(
                    time: currentTime,
                    brightness: smoothedBrightness,
                    colorTemperature: smoothedTemperature,
                    histogram: histogram
                ))

                sampleCount += 1

                if currentTime - lastEmittedTime >= effectiveSampleInterval * 10 {
                    let sortedSamples = colorSamples.sorted { $0.time < $1.time }
                    continuation.yield(sortedSamples)
                    lastEmittedTime = currentTime
                }

                currentTime += sampleInterval
            }

            if !colorSamples.isEmpty {
                let sortedSamples = colorSamples.sorted { $0.time < $1.time }
                continuation.yield(sortedSamples)
            }

            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - Bitmap Configuration

// Use noneSkipLast to get raw RGB values without alpha premultiplication
// This ensures accurate brightness/color calculations
private let rgbaBitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue

private func createRGBAContext(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext? {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    return CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: rgbaBitmapInfo
    )
}

/// Calculates average brightness (luminance) of an image
private func calculateBrightness(cgImage: CGImage) -> Double {
    let width = 64
    let height = 64
    let bytesPerPixel = 4
    let pixelCount = width * height

    var pixelData = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)

    guard let context = createRGBAContext(width: width, height: height, data: &pixelData) else {
        return 0.5
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var totalLuminance: Double = 0

    for i in 0..<pixelCount {
        let offset = i * bytesPerPixel
        let r = Double(pixelData[offset])
        let g = Double(pixelData[offset + 1])
        let b = Double(pixelData[offset + 2])

        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
        totalLuminance += luminance
    }

    return totalLuminance / Double(pixelCount)
}

/// Calculates RGB histogram for an image
private func calculateColorHistogram(cgImage: CGImage) -> ColorHistogram {
    let width = 128
    let height = 128
    let bytesPerPixel = 4
    let pixelCount = width * height

    var pixelData = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)

    guard let context = createRGBAContext(width: width, height: height, data: &pixelData) else {
        return ColorHistogram(red: Array(repeating: 0, count: 256), green: Array(repeating: 0, count: 256), blue: Array(repeating: 0, count: 256))
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var redHist = [Int](repeating: 0, count: 256)
    var greenHist = [Int](repeating: 0, count: 256)
    var blueHist = [Int](repeating: 0, count: 256)

    for i in 0..<pixelCount {
        let offset = i * bytesPerPixel
        // RGBA format (byteOrder32Big + premultipliedLast)
        let r = Int(pixelData[offset])
        let g = Int(pixelData[offset + 1])
        let b = Int(pixelData[offset + 2])
        // offset + 3 = alpha (ignored)

        redHist[r] += 1
        greenHist[g] += 1
        blueHist[b] += 1
    }

    // Normalize to 0.0-1.0 range (proportion of pixels)
    let total = Double(pixelCount)
    return ColorHistogram(
        red: redHist.map { Double($0) / total },
        green: greenHist.map { Double($0) / total },
        blue: blueHist.map { Double($0) / total }
    )
}

/// Estimates color temperature from RGB histogram using McCamy's formula
private func estimateColorTemperature(histogram: ColorHistogram) -> Double? {
    var avgR: Double = 0
    var avgG: Double = 0
    var avgB: Double = 0

    for i in 0..<256 {
        avgR += Double(i) * histogram.red[i]
        avgG += Double(i) * histogram.green[i]
        avgB += Double(i) * histogram.blue[i]
    }

    avgR /= 255.0
    avgG /= 255.0
    avgB /= 255.0

    let sum = avgR + avgG + avgB
    guard sum > 0.05 else { return nil }

    let r = avgR / sum
    let b = avgB / sum

    let warmth = (r - b) / (r + b + 0.001)

    let baseTemp = 5500.0
    let tempRange = 2500.0
    let estimatedTemp = baseTemp - (warmth * tempRange)

    return max(3000, min(8000, estimatedTemp))
}
