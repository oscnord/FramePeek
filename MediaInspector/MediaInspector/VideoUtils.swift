//
//  VideoUtils.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

struct AudioTrackInfo {
    let index: Int
    let codec: String
    let channels: Int
    let sampleRateHz: Double
    let bitrateKbps: Float?
    let languageCode: String?
}

struct ExtendedVideoInfo {
    // File
    let fileName: String
    let fileSize: String
    let overallBitrate: String
    let duration: String
    
    // Video basic
    let resolution: String
    let frameRate: String
    let codec: String
    
    // Video extra
    let orientationDegrees: Int?
    let trackBitrate: String?
    let pixelAspectRatio: String?
    let cleanAperture: String?
    let scanType: String?
    
    // Color
    let colorPrimaries: String?
    let transferFunction: String?
    let matrixCoefficients: String?
    let colorRange: String?
    let bitDepth: String?
    
    // AV1 extras
    let av1CSize: Int?
    let av1Profile: String?
    let av1Level: String?
    let av1ChromaSubsampling: String?
    let av1FullRange: String?
    
    // Metadata
    let creationDate: String?
    let metadataTitle: String?
    let metadataArtist: String?
    let metadataEncoder: String?
    let metadataDescription: String?
    
    // Audio
    let audioTracks: [AudioTrackInfo]
}

struct FrameAnalysisResult {
    let samples: [BitrateSample]
    let averageFPS: Double?
    let minInterval: Double?
    let maxInterval: Double?
}

func fourCCToString(_ code: OSType) -> String {
    let bytes: [CChar] = [
        CChar((code >> 24) & 0xFF),
        CChar((code >> 16) & 0xFF),
        CChar((code >> 8) & 0xFF),
        CChar(code & 0xFF),
        0
    ]
    return String(cString: bytes)
}

func getFileSizeString(for url: URL) -> String {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? UInt64 {
            let sizeMiB = Double(size) / 1_048_576.0 // 1024 * 1024
            return String(format: "%.2f MiB", sizeMiB)
        }
    } catch {
        print("Error getting file size: \(error.localizedDescription)")
    }
    return "Unknown"
}

func getOverallBitrateString(asset: AVAsset, fileURL: URL) async -> String {
    let durationSec: Double
    if let loadedDuration = try? await asset.load(.duration) {
        let seconds = CMTimeGetSeconds(loadedDuration)
        if seconds.isFinite, seconds > 0 {
            durationSec = seconds
        } else {
            return "Unknown"
        }
    } else {
        return "Unknown"
    }
    
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs[.size] as? UInt64 {
            let totalBits = Double(size) * 8.0
            let bitsPerSecond = totalBits / durationSec
            let kbps = bitsPerSecond / 1000.0 // kbit/s (decimal)
            return String(format: "%.0f kb/s", kbps)
        }
    } catch {
        print("Error getting overall bitrate: \(error.localizedDescription)")
    }
    return "Unknown"
}

struct AV1ConfigSummary {
    let profile: Int
    let level: Int
    let bitDepth: Int
    let chromaSubsampling: String
    let fullRange: Bool
}

func parseAV1C(_ data: Data) -> AV1ConfigSummary? {
    guard data.count >= 4 else { return nil }
    let bytes = [UInt8](data)
    
    // Byte 1: profile (bits 5..7)
    let profile = Int((bytes[1] & 0b1110_0000) >> 5)
    // Byte 2: level (bits 0..4)
    let level = Int(bytes[2] & 0b0001_1111)
    
    let seqProfile = profile
    let highBitDepth = (bytes[2] & 0b0010_0000) != 0
    let twelveBit = (bytes[2] & 0b0100_0000) != 0
    
    let bitDepth: Int
    if seqProfile == 2 {
        bitDepth = highBitDepth ? 12 : 10
    } else {
        bitDepth = twelveBit ? 12 : (highBitDepth ? 10 : 8)
    }
    
    let monoChrome = (bytes[3] & 0b1000_0000) != 0
    let subsamplingX = (bytes[3] & 0b0100_0000) != 0
    let subsamplingY = (bytes[3] & 0b0010_0000) != 0
    
    let chroma: String
    if monoChrome {
        chroma = "Monochrome"
    } else if !subsamplingX && !subsamplingY {
        chroma = "4:4:4"
    } else if subsamplingX && !subsamplingY {
        chroma = "4:2:2"
    } else if subsamplingX && subsamplingY {
        chroma = "4:2:0"
    } else {
        chroma = "Unknown"
    }
    
    let fullRange = (bytes[3] & 0b0000_1000) != 0
    
    return AV1ConfigSummary(
        profile: profile,
        level: level,
        bitDepth: bitDepth,
        chromaSubsampling: chroma,
        fullRange: fullRange
    )
}

private func formatCreationDate(from asset: AVAsset) async -> String? {
    guard
        let creationItem = try? await asset.load(.creationDate),
        let date = creationItem.dateValue
    else {
        return nil
    }
    
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

private func extractCommonMetadata(from asset: AVAsset) -> (
    title: String?,
    artist: String?,
    encoder: String?,
    description: String?
) {
    var title: String?
    var artist: String?
    var encoder: String?
    var description: String?
    
    for item in asset.commonMetadata {
        guard let commonKey = item.commonKey?.rawValue,
              let value = item.stringValue else { continue }
        
        switch commonKey {
        case "title":
            if title == nil { title = value }
        case "artist":
            if artist == nil { artist = value }
        case "encoder":
            if encoder == nil { encoder = value }
        case "description":
            if description == nil { description = value }
        default:
            break
        }
    }
    
    return (title, artist, encoder, description)
}

func loadAudioInfo(asset: AVAsset) async -> [AudioTrackInfo] {
    var result: [AudioTrackInfo] = []
    
    let tracks: [AVAssetTrack]
    do {
        tracks = try await asset.loadTracks(withMediaType: .audio)
    } catch {
        print("Failed to load audio tracks: \(error.localizedDescription)")
        return []
    }
    
    for (idx, track) in tracks.enumerated() {
        let index = idx + 1
        
        var codec = "Unknown"
        var channels = 0
        var sampleRateHz: Double = 0
        
        let formatDescs = track.formatDescriptions as? [CMAudioFormatDescription] ?? []
        if let audioDesc = formatDescs.first {
            let codecFourCC = CMFormatDescriptionGetMediaSubType(audioDesc)
            codec = fourCCToString(codecFourCC)
            
            if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc) {
                let asbd = asbdPtr.pointee
                channels = Int(asbd.mChannelsPerFrame)
                sampleRateHz = asbd.mSampleRate
            }
        }
        
        let bitrateBps: Float = track.estimatedDataRate
        let bitrateKbps: Float? = bitrateBps > 0 ? bitrateBps / 1000.0 : nil
        let languageCode = track.languageCode
        
        result.append(
            AudioTrackInfo(
                index: index,
                codec: codec,
                channels: channels,
                sampleRateHz: sampleRateHz,
                bitrateKbps: bitrateKbps,
                languageCode: languageCode
            )
        )
    }
    
    return result
}

func getExtendedInfo(url: URL, asset: AVAsset) async -> ExtendedVideoInfo {
    let fileName = url.lastPathComponent
    let fileSize = getFileSizeString(for: url)
    let overallBitrate = await getOverallBitrateString(asset: asset, fileURL: url)
    
    var duration = "N/A"
    var resolution = "N/A"
    var frameRate = "N/A"
    var codec = "Unknown"
    
    var orientationDegrees: Int? = nil
    var trackBitrate: String? = nil
    var pixelAspectRatio: String? = nil
    var cleanAperture: String? = nil
    var scanType: String? = nil
    
    var colorPrimaries: String? = nil
    var transferFunction: String? = nil
    var matrixCoefficients: String? = nil
    var colorRange: String? = nil
    
    var inferredBitDepthBpc: Int? = nil
    
    var av1CSize: Int? = nil
    var av1Profile: String? = nil
    var av1Level: String? = nil
    var av1Chroma: String? = nil
    var av1Range: String? = nil
    
    if let loadedDuration = try? await asset.load(.duration) {
        let durationSec = CMTimeGetSeconds(loadedDuration)
        if durationSec > 0 {
            duration = String(format: "%.2f sec", durationSec)
        }
    }
    
    let creationDateString = await formatCreationDate(from: asset)
    let metadata = extractCommonMetadata(from: asset)
    
    var videoTrack: AVAssetTrack?
    do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        videoTrack = tracks.first
    } catch {
        print("Failed to load video tracks: \(error.localizedDescription)")
        videoTrack = nil
    }
    
    if let videoTrack = videoTrack {
        do {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let loadedFrameRate = try await videoTrack.load(.nominalFrameRate)
            
            let w = Int(naturalSize.width)
            let h = Int(naturalSize.height)
            resolution = "\(w)x\(h)"
            frameRate = String(format: "%.2f FPS", loadedFrameRate)
            
            // Orientation (preferredTransform)
            let t = videoTrack.preferredTransform
            let angle = atan2(t.b, t.a) * 180.0 / .pi
            let normalized = (Int(round(angle)) % 360 + 360) % 360
            orientationDegrees = normalized
            
            // Track bitrate
            let estimated = videoTrack.estimatedDataRate
            if estimated > 0 {
                trackBitrate = String(format: "%.0f kb/s", estimated / 1000.0)
            }
            
            // Format description + color / AV1 / PAR / clean aperture
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                // Codec
                let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                let codecID = fourCCToString(codecType)
                let codecMappings: [String: String] = [
                    "avc1": "H.264",
                    "hvc1": "HEVC (H.265)",
                    "vp09": "VP9",
                    "av01": "AV1"
                ]
                codec = codecMappings[codecID] ?? codecID
                
                if let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] {
                    // Color primaries & transfer function
                    colorPrimaries = extDict[kCMFormatDescriptionExtension_ColorPrimaries] as? String
                    transferFunction = extDict[kCMFormatDescriptionExtension_TransferFunction] as? String
                    
                    // Matrix coefficients
                    if let matrix = extDict[kCMFormatDescriptionExtension_YCbCrMatrix] as? String {
                        matrixCoefficients = matrix
                    }
                    
                    // Color range
                    if let fullRangeNumber = extDict[kCMFormatDescriptionExtension_FullRangeVideo] as? NSNumber {
                        colorRange = fullRangeNumber.boolValue ? "Full" : "Limited"
                    }
                    
                    // Bit depth
                    if let bpc = extDict[kCMFormatDescriptionExtension_BitsPerComponent] as? NSNumber {
                        inferredBitDepthBpc = bpc.intValue
                    }
                    
                    // Clean aperture
                    if let caDict = extDict[kCMFormatDescriptionExtension_CleanAperture] as? [CFString: Any],
                       let w = caDict[kCMFormatDescriptionKey_CleanApertureWidth] as? NSNumber,
                       let h = caDict[kCMFormatDescriptionKey_CleanApertureHeight] as? NSNumber {
                        cleanAperture = "\(w.intValue)x\(h.intValue)"
                    }
                    
                    // Pixel aspect ratio
                    if let parDict = extDict[kCMFormatDescriptionExtension_PixelAspectRatio] as? [CFString: Any],
                       let h = parDict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] as? NSNumber,
                       let v = parDict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] as? NSNumber {
                        pixelAspectRatio = "\(h.intValue):\(v.intValue)"
                    }
                    
                    // Scan type
                    if let fieldCount = extDict[kCMFormatDescriptionExtension_FieldCount] as? NSNumber {
                        switch fieldCount.intValue {
                        case 1: scanType = "Progressive"
                        case 2: scanType = "Interlaced (2 fields)"
                        default: scanType = "Interlaced"
                        }
                    }
                    
                    // AV1 sample description if present
                    if let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any],
                       let av1CData = atoms["av1C" as CFString] as? Data {
                        av1CSize = av1CData.count
                        if let cfg = parseAV1C(av1CData) {
                            av1Profile = "Profile \(cfg.profile)"
                            av1Level = "Level \(cfg.level)"
                            av1Chroma = cfg.chromaSubsampling
                            av1Range = cfg.fullRange ? "Full" : "Limited"

                            inferredBitDepthBpc = cfg.bitDepth
                        }
                    }
                }
            }
        } catch {
            print("Error loading extended video info: \(error.localizedDescription)")
        }
    }
    
    let bitDepthString: String?
    if let bpc = inferredBitDepthBpc {
        bitDepthString = "\(bpc)-bit"
    } else {
        bitDepthString = nil
    }
    
    let audioTracks = await loadAudioInfo(asset: asset)
    
    return ExtendedVideoInfo(
        fileName: fileName,
        fileSize: fileSize,
        overallBitrate: overallBitrate,
        duration: duration,
        resolution: resolution,
        frameRate: frameRate,
        codec: codec,
        orientationDegrees: orientationDegrees,
        trackBitrate: trackBitrate,
        pixelAspectRatio: pixelAspectRatio,
        cleanAperture: cleanAperture,
        scanType: scanType,
        colorPrimaries: colorPrimaries,
        transferFunction: transferFunction,
        matrixCoefficients: matrixCoefficients,
        colorRange: colorRange,
        bitDepth: bitDepthString,
        av1CSize: av1CSize,
        av1Profile: av1Profile,
        av1Level: av1Level,
        av1ChromaSubsampling: av1Chroma,
        av1FullRange: av1Range,
        creationDate: creationDateString,
        metadataTitle: metadata.title,
        metadataArtist: metadata.artist,
        metadataEncoder: metadata.encoder,
        metadataDescription: metadata.description,
        audioTracks: audioTracks
    )
}

func frameRateStats(from times: [Double]) -> (averageFPS: Double, minInterval: Double, maxInterval: Double)? {
    guard times.count > 1 else { return nil }
    
    var intervals: [Double] = []
    intervals.reserveCapacity(times.count - 1)
    
    for i in 1..<times.count {
        let interval = times[i] - times[i - 1]
        if interval > 0 {
            intervals.append(interval)
        }
    }
    
    guard !intervals.isEmpty else { return nil }
    
    let totalDuration = intervals.reduce(0, +)
    let averageInterval = totalDuration / Double(intervals.count)
    let averageFPS = averageInterval > 0 ? 1.0 / averageInterval : 0
    let minInterval = intervals.min() ?? 0
    let maxInterval = intervals.max() ?? 0
    
    return (averageFPS, minInterval, maxInterval)
}

func extractFrames(
    asset: AVAsset,
    maxSamples: Int = 2000,
    completion: @escaping (FrameAnalysisResult) -> Void
) {
    let emptyResult = FrameAnalysisResult(
        samples: [],
        averageFPS: nil,
        minInterval: nil,
        maxInterval: nil
    )
    
    Task {
        let durationSeconds: Double
        if let durationTime = try? await asset.load(.duration) {
            let s = CMTimeGetSeconds(durationTime)
            durationSeconds = (s.isFinite && s > 0) ? s : 0
        } else {
            durationSeconds = 0
        }
        
        let videoTrack: AVAssetTrack?
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            videoTrack = tracks.first
        } catch {
            print("Failed to load video tracks for extraction: \(error.localizedDescription)")
            videoTrack = nil
        }
        
        guard let videoTrack else {
            DispatchQueue.main.async {
                completion(emptyResult)
            }
            return
        }
        
        // Create reader & output
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            print("Failed to create AVAssetReader: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(emptyResult)
            }
            return
        }
        
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false  // avoid copying sample data if possible
        
        guard reader.canAdd(output) else {
            print("Reader cannot add output")
            DispatchQueue.main.async {
                completion(emptyResult)
            }
            return
        }
        reader.add(output)
        
        let minStep = (durationSeconds > 0 && maxSamples > 0)
        ? durationSeconds / Double(maxSamples)
        : 0
        
        DispatchQueue.global(qos: .userInitiated).async { [reader, output] in
            guard reader.startReading() else {
                print("Reader failed to start: \(reader.error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    completion(emptyResult)
                }
                return
            }
            
            var samples: [BitrateSample] = []
            samples.reserveCapacity(maxSamples)
            
            var previousTimeForBitrate: Double?
            var previousTimeForStats: Double?
            var lastEmittedTime: Double?
            
            var sumInterval = 0.0
            var intervalCount = 0
            var minIntervalVal = Double.greatestFiniteMagnitude
            var maxIntervalVal = 0.0
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                autoreleasepool {
                    let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                    let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
                    
                    // Stats for FPS / min / max interval (uses EVERY frame)
                    if let prev = previousTimeForStats, currentTime > prev {
                        let interval = currentTime - prev
                        sumInterval += interval
                        intervalCount += 1
                        if interval < minIntervalVal { minIntervalVal = interval }
                        if interval > maxIntervalVal { maxIntervalVal = interval }
                    }
                    previousTimeForStats = currentTime
                    
                    // Per-frame bitrate (between frames)
                    if let prev = previousTimeForBitrate, currentTime > prev {
                        let frameDuration = currentTime - prev
                        if frameDuration > 0 {
                            let frameBitrate = (Double(sampleSize) * 8.0) / frameDuration
                            
                            // Decide whether to keep this point for plotting
                            let shouldEmit: Bool
                            if minStep > 0 {
                                if let last = lastEmittedTime {
                                    shouldEmit = currentTime - last >= minStep
                                } else {
                                    shouldEmit = true
                                }
                            } else {
                                shouldEmit = true
                            }
                            
                            if shouldEmit {
                                samples.append(
                                    BitrateSample(
                                        time: currentTime,
                                        bitrate: frameBitrate
                                    )
                                )
                                lastEmittedTime = currentTime
                            }
                        }
                    }
                    
                    previousTimeForBitrate = currentTime
                }
            }
            
            if reader.status != .completed {
                print("Reader finished with status \(reader.status): \(reader.error?.localizedDescription ?? "No error")")
            }
            
            let avgFPS: Double?
            let minInt: Double?
            let maxInt: Double?
            
            if intervalCount > 0 {
                let avgInterval = sumInterval / Double(intervalCount)
                avgFPS = avgInterval > 0 ? 1.0 / avgInterval : nil
                minInt = minIntervalVal
                maxInt = maxIntervalVal
            } else {
                avgFPS = nil
                minInt = nil
                maxInt = nil
            }
            
            let result = FrameAnalysisResult(
                samples: samples,
                averageFPS: avgFPS,
                minInterval: minInt,
                maxInterval: maxInt
            )
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
