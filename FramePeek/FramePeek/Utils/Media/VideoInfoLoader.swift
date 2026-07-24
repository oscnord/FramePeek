import Foundation
import AVFoundation
import CoreMedia

// MARK: - Extended Video Info Loader

/// Loads comprehensive video information from a file URL and AVAsset
/// Uses parallel extraction for improved performance
/// - Parameters:
///   - url: File URL of the video
///   - asset: AVAsset instance for the video
/// - Returns: ExtendedVideoInfo containing all available metadata
public func getExtendedInfo(url: URL, asset: AVAsset) async -> ExtendedVideoInfo {
    // Synchronous operations
    let basicInfo = extractBasicInfo(url: url)

    // Parallel async operations - all run concurrently
    async let durationInfo = extractDurationInfo(asset: asset)
    async let overallBitrate = getOverallBitrateString(asset: asset, fileURL: url)
    async let metadataInfo = extractMetadataInfo(asset: asset)
    async let audioTracks = loadAudioInfo(asset: asset)

    // Load the video track and its format description once; codec, color,
    // and AV1 extraction are plain dictionary reads on the same description
    var videoInfo: VideoTrackInfo?
    var codecInfo: CodecInfo?
    var colorInfo: ColorInfo?
    var av1Info: AV1Info?

    if let videoTrack = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) {
        let formatDescription = (try? await videoTrack.load(.formatDescriptions))?.first

        videoInfo = await extractVideoTrackInfo(videoTrack: videoTrack, formatDescription: formatDescription)
        codecInfo = extractCodecInfo(formatDescription: formatDescription)
        colorInfo = extractColorInfo(
            formatDescription: formatDescription,
            hasDolbyVision: codecInfo?.hasDolbyVision ?? false
        )
        av1Info = extractAV1Info(formatDescription: formatDescription)
    }

    // Wait for the remaining parallel operations
    let (duration, bitrate, metadata, audio) = await (
        durationInfo, overallBitrate, metadataInfo, audioTracks
    )

    // Combine all extracted information
    let videoWidth = videoInfo?.videoWidth ?? 0
    let videoHeight = videoInfo?.videoHeight ?? 0
    let parH = videoInfo?.parH ?? 1
    let parV = videoInfo?.parV ?? 1
    let nominalFrameRateValue = videoInfo?.nominalFrameRateValue ?? 0
    let trackBitrateValue = videoInfo?.trackBitrateValue ?? 0

    // Calculate display aspect ratio
    let displayAspectRatio: String? = {
    if videoWidth > 0 && videoHeight > 0 {
            return calculateDisplayAspectRatio(
            width: videoWidth,
            height: videoHeight,
            parH: parH,
            parV: parV
        )
    }
        return nil
    }()

    // Determine final chroma subsampling (prefer AV1, then codec, then color)
    let chromaSubsampling = av1Info?.chromaSubsampling ?? codecInfo?.chromaSubsampling ?? colorInfo?.chromaSubsampling

    // Determine final bit depth (prefer AV1, then color)
    let inferredBitDepthBpc = av1Info?.inferredBitDepthBpc ?? colorInfo?.inferredBitDepthBpc
    let bitDepthString: String? = inferredBitDepthBpc.map { "\($0)-bit" }

    // Calculate bits per pixel per frame
    let bitsPerPixelFrame: String? = {
    if videoWidth > 0 && videoHeight > 0 && nominalFrameRateValue > 0 && trackBitrateValue > 0 {
        let pixelsPerFrame = Double(videoWidth * videoHeight)
        let bitsPerSecond = Double(trackBitrateValue)
        let framesPerSecond = Double(nominalFrameRateValue)
        let bppf = bitsPerSecond / (pixelsPerFrame * framesPerSecond)
            return String(format: "%.3f", bppf)
    }
        return nil
    }()

    // Calculate video stream size (estimate based on bitrate ratio)
    let videoStreamSize: String? = {
        guard let fileSizeBytes = basicInfo.fileSizeBytes,
              duration.durationSec > 0,
              trackBitrateValue > 0 else {
            return nil
        }
        let totalBits = Double(fileSizeBytes) * 8.0
        let totalBitrate = totalBits / duration.durationSec
        let videoRatio = Double(trackBitrateValue) / totalBitrate
        let videoBytes = Double(fileSizeBytes) * videoRatio
        let videoGiB = videoBytes / (1024.0 * 1024.0 * 1024.0)
        let percentage = videoRatio * 100.0
        if videoGiB >= 1.0 {
            return String(format: "%.2f GiB (%.0f%%)", videoGiB, percentage)
        } else {
            let videoMiB = videoBytes / (1024.0 * 1024.0)
            return String(format: "%.2f MiB (%.0f%%)", videoMiB, percentage)
        }
    }()

    return ExtendedVideoInfo(
        fileName: basicInfo.fileName,
        fileSize: basicInfo.fileSize,
        fileSizeBytes: basicInfo.fileSizeBytes,
        overallBitrate: bitrate,
        duration: duration.duration,
        durationFormatted: duration.durationFormatted,
        containerFormat: basicInfo.containerFormat,
        containerFormatProfile: basicInfo.containerFormatProfile,
        codecIdRaw: codecInfo?.codecIdRaw,
        resolution: videoInfo?.resolution ?? "N/A",
        displayAspectRatio: displayAspectRatio,
        frameRate: videoInfo?.frameRate ?? "N/A",
        codec: codecInfo?.codec ?? "Unknown",
        codecProfile: codecInfo?.codecProfile ?? av1Info?.av1Profile,
        codecIdInfo: codecInfo?.codecIdInfo,
        orientationDegrees: videoInfo?.orientationDegrees,
        trackBitrate: videoInfo?.trackBitrate,
        maxBitrate: codecInfo?.maxBitrate,
        minBitrate: nil,
        pixelAspectRatio: videoInfo?.pixelAspectRatio,
        cleanAperture: videoInfo?.cleanAperture,
        scanType: videoInfo?.scanType,
        frameRateMode: videoInfo?.frameRateMode,
        colorSpace: colorInfo?.colorSpace,
        chromaSubsampling: chromaSubsampling,
        bitsPerPixelFrame: bitsPerPixelFrame,
        videoStreamSize: videoStreamSize,
        colorPrimaries: colorInfo?.colorPrimaries,
        transferFunction: colorInfo?.transferFunction,
        matrixCoefficients: colorInfo?.matrixCoefficients,
        colorRange: colorInfo?.colorRange,
        bitDepth: bitDepthString,
        hdrFormat: colorInfo?.hdrFormat,
        av1CSize: av1Info?.av1CSize,
        av1Profile: av1Info?.av1Profile,
        av1Level: av1Info?.av1Level,
        av1ChromaSubsampling: av1Info?.av1Chroma,
        av1FullRange: av1Info?.av1Range,
        creationDate: metadata.creationDate,
        metadataTitle: metadata.title,
        metadataArtist: metadata.artist,
        metadataEncoder: metadata.encoder,
        metadataDescription: metadata.description,
        audioTracks: audio
    )
}
