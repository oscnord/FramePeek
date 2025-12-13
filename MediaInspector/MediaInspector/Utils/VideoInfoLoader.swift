//
//  VideoInfoLoader.swift
//  MediaInspector
//
//  Main loader for extended video information from AVAsset.
//

import Foundation
import AVFoundation
import CoreMedia

// MARK: - Metadata Extraction

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

// MARK: - Extended Video Info Loader

/// Loads comprehensive video information from a file URL and AVAsset
/// - Parameters:
///   - url: File URL of the video
///   - asset: AVAsset instance for the video
/// - Returns: ExtendedVideoInfo containing all available metadata
func getExtendedInfo(url: URL, asset: AVAsset) async -> ExtendedVideoInfo {
    let fileName = url.lastPathComponent
    let fileSize = getFileSizeString(for: url)
    let fileSizeBytes = getFileSizeBytes(for: url)
    let overallBitrate = await getOverallBitrateString(asset: asset, fileURL: url)
    
    var duration = "N/A"
    var durationFormatted = "N/A"
    var durationSec: Double = 0
    var resolution = "N/A"
    var displayAspectRatio: String? = nil
    var frameRate = "N/A"
    var nominalFrameRateValue: Float = 0
    var codec = "Unknown"
    var codecIdRaw: String? = nil
    var codecProfile: String? = nil
    var codecIdInfo: String? = nil
    
    // Container format
    var containerFormat: String? = nil
    var containerFormatProfile: String? = nil
    
    var orientationDegrees: Int? = nil
    var trackBitrate: String? = nil
    var trackBitrateValue: Float = 0
    var maxBitrate: String? = nil
    var pixelAspectRatio: String? = nil
    var cleanAperture: String? = nil
    var scanType: String? = nil
    var frameRateMode: String? = nil
    var colorSpace: String? = nil
    var chromaSubsampling: String? = nil
    var videoStreamSize: String? = nil
    var bitsPerPixelFrame: String? = nil
    
    var colorPrimaries: String? = nil
    var transferFunction: String? = nil
    var matrixCoefficients: String? = nil
    var colorRange: String? = nil
    var hdrFormat: String? = nil
    var hasDolbyVision = false
    
    var inferredBitDepthBpc: Int? = nil
    
    var av1CSize: Int? = nil
    var av1Profile: String? = nil
    var av1Level: String? = nil
    var av1Chroma: String? = nil
    var av1Range: String? = nil
    
    // PAR values for aspect ratio calculation
    var parH: Int = 1
    var parV: Int = 1
    var videoWidth: Int = 0
    var videoHeight: Int = 0
    
    // Detect container format from file extension and AVAsset
    containerFormat = detectContainerFormat(url: url)
    
    if let loadedDuration = try? await asset.load(.duration) {
        durationSec = CMTimeGetSeconds(loadedDuration)
        if durationSec > 0 {
            duration = String(format: "%.2f sec", durationSec)
            durationFormatted = formatDuration(seconds: durationSec)
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
            videoWidth = w
            videoHeight = h
            resolution = "\(w)x\(h)"
            nominalFrameRateValue = loadedFrameRate
            frameRate = String(format: "%.3f FPS", loadedFrameRate)
            
            // Orientation (preferredTransform)
            let t = videoTrack.preferredTransform
            let angle = atan2(t.b, t.a) * 180.0 / .pi
            let normalized = (Int(round(angle)) % 360 + 360) % 360
            orientationDegrees = normalized
            
            // Track bitrate
            let estimated = videoTrack.estimatedDataRate
            if estimated > 0 {
                trackBitrateValue = estimated
                trackBitrate = String(format: "%.0f kb/s", estimated / 1000.0)
            }
            
            // Format description + color / AV1 / PAR / clean aperture
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                // Codec
                let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                let codecID = fourCCToString(codecType)
                codecIdRaw = codecID.trimmingCharacters(in: .whitespaces)
                codec = videoCodecName(codecID)
                codecIdInfo = videoCodecInfo(codecID)
                
                if let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] {
                    // Color primaries & transfer function
                    colorPrimaries = extDict[kCMFormatDescriptionExtension_ColorPrimaries] as? String
                    transferFunction = extDict[kCMFormatDescriptionExtension_TransferFunction] as? String
                    
                    // Matrix coefficients (indicates YUV color space)
                    if let matrix = extDict[kCMFormatDescriptionExtension_YCbCrMatrix] as? String {
                        matrixCoefficients = matrix
                        colorSpace = "YUV" // If matrix is present, it's YUV
                    }
                    
                    // Color range
                    if let fullRangeNumber = extDict[kCMFormatDescriptionExtension_FullRangeVideo] as? NSNumber {
                        colorRange = fullRangeNumber.boolValue ? "Full" : "Limited"
                    }
                    
                    // Bit depth
                    if let bpc = extDict[kCMFormatDescriptionExtension_BitsPerComponent] as? NSNumber {
                        inferredBitDepthBpc = bpc.intValue
                    }
                    
                    // Depth (for chroma subsampling detection)
                    if let depth = extDict[kCMFormatDescriptionExtension_Depth] as? NSNumber {
                        // 24-bit typically means 4:4:4, 12-bit means 4:2:0
                        let depthValue = depth.intValue
                        if chromaSubsampling == nil {
                            if depthValue == 24 {
                                chromaSubsampling = "4:4:4"
                            } else if depthValue == 12 {
                                chromaSubsampling = "4:2:0"
                            }
                        }
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
                        parH = h.intValue
                        parV = v.intValue
                        pixelAspectRatio = "\(parH):\(parV)"
                    }
                    
                    // Scan type
                    if let fieldCount = extDict[kCMFormatDescriptionExtension_FieldCount] as? NSNumber {
                        switch fieldCount.intValue {
                        case 1: scanType = "Progressive"
                        case 2: scanType = "Interlaced (2 fields)"
                        default: scanType = "Interlaced"
                        }
                    }
                    
                    // Sample description extension atoms
                    if let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any] {
                        // Check for Dolby Vision configuration
                        if atoms["dvcC" as CFString] != nil || atoms["dvvC" as CFString] != nil {
                            hasDolbyVision = true
                        }
                        
                        // HEVC config (hvcC)
                        if let hvcCData = atoms["hvcC" as CFString] as? Data {
                            if let profile = parseHEVCProfile(hvcCData) {
                                codecProfile = profile
                            }
                            // HEVC is typically 4:2:0
                            if chromaSubsampling == nil {
                                chromaSubsampling = "4:2:0"
                            }
                        }
                        
                        // AVC config (avcC)
                        if let avcCData = atoms["avcC" as CFString] as? Data {
                            if let profile = parseAVCProfile(avcCData) {
                                codecProfile = profile
                            }
                            // AVC is typically 4:2:0
                            if chromaSubsampling == nil {
                                chromaSubsampling = "4:2:0"
                            }
                        }
                        
                        // VP9 config
                        if let vpcCData = atoms["vpcC" as CFString] as? Data {
                            if let profile = parseVP9Profile(vpcCData) {
                                codecProfile = profile
                            }
                        }
                        
                        // AV1 config
                        if let av1CData = atoms["av1C" as CFString] as? Data {
                            av1CSize = av1CData.count
                            if let cfg = parseAV1C(av1CData) {
                                av1Profile = "Profile \(cfg.profile)"
                                av1Level = "Level \(cfg.level)"
                                av1Chroma = cfg.chromaSubsampling
                                chromaSubsampling = cfg.chromaSubsampling
                                av1Range = cfg.fullRange ? "Full" : "Limited"
                                inferredBitDepthBpc = cfg.bitDepth
                                codecProfile = "Main"
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error loading extended video info: \(error.localizedDescription)")
        }
    }
    
    // Calculate display aspect ratio
    if videoWidth > 0 && videoHeight > 0 {
        displayAspectRatio = calculateDisplayAspectRatio(
            width: videoWidth,
            height: videoHeight,
            parH: parH,
            parV: parV
        )
    }
    
    // Detect HDR format
    hdrFormat = detectHDRFormat(
        transferFunction: transferFunction,
        colorPrimaries: colorPrimaries,
        hasDolbyVisionConfig: hasDolbyVision
    )
    
    let bitDepthString: String?
    if let bpc = inferredBitDepthBpc {
        bitDepthString = "\(bpc)-bit"
    } else {
        bitDepthString = nil
    }
    
    // Calculate bits per pixel per frame
    if videoWidth > 0 && videoHeight > 0 && nominalFrameRateValue > 0 && trackBitrateValue > 0 {
        let pixelsPerFrame = Double(videoWidth * videoHeight)
        let bitsPerSecond = Double(trackBitrateValue)
        let framesPerSecond = Double(nominalFrameRateValue)
        let bppf = bitsPerSecond / (pixelsPerFrame * framesPerSecond)
        bitsPerPixelFrame = String(format: "%.3f", bppf)
    }
    
    // Calculate video stream size (estimate based on bitrate ratio)
    if let fileSizeBytes = fileSizeBytes, durationSec > 0 && trackBitrateValue > 0 {
        let totalBits = Double(fileSizeBytes) * 8.0
        let totalBitrate = totalBits / durationSec
        let videoRatio = Double(trackBitrateValue) / totalBitrate
        let videoBytes = Double(fileSizeBytes) * videoRatio
        let videoGiB = videoBytes / (1024.0 * 1024.0 * 1024.0)
        let percentage = videoRatio * 100.0
        if videoGiB >= 1.0 {
            videoStreamSize = String(format: "%.2f GiB (%.0f%%)", videoGiB, percentage)
        } else {
            let videoMiB = videoBytes / (1024.0 * 1024.0)
            videoStreamSize = String(format: "%.2f MiB (%.0f%%)", videoMiB, percentage)
        }
    }
    
    let audioTracks = await loadAudioInfo(asset: asset)
    
    return ExtendedVideoInfo(
        fileName: fileName,
        fileSize: fileSize,
        fileSizeBytes: fileSizeBytes,
        overallBitrate: overallBitrate,
        duration: duration,
        durationFormatted: durationFormatted,
        containerFormat: containerFormat,
        containerFormatProfile: containerFormatProfile,
        codecIdRaw: codecIdRaw,
        resolution: resolution,
        displayAspectRatio: displayAspectRatio,
        frameRate: frameRate,
        codec: codec,
        codecProfile: codecProfile,
        codecIdInfo: codecIdInfo,
        orientationDegrees: orientationDegrees,
        trackBitrate: trackBitrate,
        maxBitrate: maxBitrate,
        pixelAspectRatio: pixelAspectRatio,
        cleanAperture: cleanAperture,
        scanType: scanType,
        frameRateMode: frameRateMode,
        colorSpace: colorSpace,
        chromaSubsampling: chromaSubsampling,
        bitsPerPixelFrame: bitsPerPixelFrame,
        videoStreamSize: videoStreamSize,
        colorPrimaries: colorPrimaries,
        transferFunction: transferFunction,
        matrixCoefficients: matrixCoefficients,
        colorRange: colorRange,
        bitDepth: bitDepthString,
        hdrFormat: hdrFormat,
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
