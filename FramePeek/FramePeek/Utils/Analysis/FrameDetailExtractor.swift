import AVFoundation
import CoreMedia

// MARK: - Frame Detail Extractor

/// Extracts frame-level details with accurate frame type detection.
/// Only provides frame types for supported codecs (H.264, HEVC, intra-only).
public enum FrameDetailExtractor {
    
    /// Result of frame detail extraction
    public struct ExtractionResult: Sendable {
        public let frames: [FrameInfo]
        public let codecSupportsFrameTypes: Bool
        public let codecName: String
    }
    
    /// Extracts frame details for a specific time range.
    /// - Parameters:
    ///   - asset: The video asset to analyze
    ///   - timeRange: The time range to extract frames from
    /// - Returns: Extraction result with frames and codec support info, or nil if extraction fails
    public static func extractFrameDetails(
        from asset: AVAsset,
        timeRange: ClosedRange<Double>
    ) async -> ExtractionResult? {
        guard let track = await AVAssetLoader.firstTrack(of: asset, mediaType: .video) else {
            return nil
        }

        // Get codec type
        var codecType: FourCharCode?
        var codecName = "Unknown"
        if let firstDesc = await AVAssetLoader.firstFormatDescription(of: track) {
            codecType = CMFormatDescriptionGetMediaSubType(firstDesc)
            if let code = codecType {
                codecName = fourCCToString(code)
            }
        }
        
        // Determine if codec supports frame type detection
        let supportsFrameTypes: Bool
        if let code = codecType {
            supportsFrameTypes = codecSupportsFrameTypeDetection(code)
        } else {
            supportsFrameTypes = false
        }
        
        // If codec doesn't support frame types, return early with empty frames
        if !supportsFrameTypes {
            return ExtractionResult(
                frames: [],
                codecSupportsFrameTypes: false,
                codecName: codecName
            )
        }
        
        // Check if intra-only codec (all I-frames)
        let isIntraOnly = codecType.map { isIntraOnlyCodec($0) } ?? false
        
        do {
            let reader = try AVAssetReader(asset: asset)
            
            // Set time range to limit reading
            let startTime = CMTime(seconds: timeRange.lowerBound, preferredTimescale: 600)
            let duration = CMTime(seconds: timeRange.upperBound - timeRange.lowerBound + 0.5, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: startTime, duration: duration)
            
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            
            guard reader.startReading() else { return nil }
            
            var frames: [FrameInfo] = []
            frames.reserveCapacity(200)
            
            while let sampleBuffer = output.copyNextSampleBuffer() {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                
                guard pts.isFinite else { continue }
                
                // Stop if we've passed the range
                if pts > timeRange.upperBound + 0.1 { break }
                
                // Skip if before range
                if pts < timeRange.lowerBound - 0.1 { continue }
                
                // Detect frame type
                let frameType: FrameType
                if isIntraOnly {
                    frameType = .i
                } else if let code = codecType {
                    frameType = detectFrameTypeEnhanced(sampleBuffer: sampleBuffer, codecType: code)
                } else {
                    frameType = .unknown
                }
                
                // Get frame size
                var frameSize: Int64?
                if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    var totalLength: Int = 0
                    CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: nil)
                    frameSize = Int64(totalLength)
                }
                
                frames.append(FrameInfo(time: pts, type: frameType, size: frameSize))
            }
            
            return ExtractionResult(
                frames: frames.sorted { $0.time < $1.time },
                codecSupportsFrameTypes: true,
                codecName: codecName
            )
        } catch {
            Log.analysis.error("FrameDetailExtractor: Failed to extract frame details - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Checks if codec supports accurate frame type detection
    public static func codecSupportsFrameTypeDetection(_ codecType: FourCharCode) -> Bool {
        return isIntraOnlyCodec(codecType) || supportsNALFrameTypeDetection(codecType)
    }
    
    // MARK: - Enhanced Frame Type Detection
    
    /// Enhanced frame type detection with multiple fallback strategies.
    /// Only called for H.264/HEVC codecs.
    private static func detectFrameTypeEnhanced(
        sampleBuffer: CMSampleBuffer,
        codecType: FourCharCode
    ) -> FrameType {
        // Step 1: Check sync sample (reliable keyframe detection)
        if isSyncSample(sampleBuffer) {
            return .i
        }
        
        // Step 2: Try NAL unit parsing (most accurate for H.264/HEVC)
        let nalResult = detectFrameType(sampleBuffer: sampleBuffer, codecType: codecType)
        if nalResult != .unknown {
            return nalResult
        }
        
        // Step 3: Try sample attachment heuristic
        if let attachmentResult = detectFrameTypeFromAttachments(sampleBuffer) {
            return attachmentResult
        }
        
        // Step 4: Safe fallback - assume P-frame for non-keyframes
        // (Most non-keyframes are P or B; P is safer default)
        return .p
    }
    
    /// Checks if sample is a sync sample (keyframe) using attachments
    private static func isSyncSample(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0,
              let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as? [CFString: Any] else {
            // No attachments - assume sync sample
            return true
        }
        
        let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        return !notSync
    }
}

// MARK: - Codec Classification

/// Set of intra-only codec FourCCs (all frames are I-frames)
private let intraOnlyCodecFourCCs: Set<String> = [
    "apch", "apcn", "apcs", "apco", "ap4h", "ap4x",  // ProRes
    "aprn", "aprh",                                    // ProRes RAW
    "AVdn",                                            // DNxHD/DNxHR
    "mjpa", "mjpb",                                    // MJPEG
    "dvc ", "dvcp", "dvpp",                            // DV
    "raw ", "v210",                                    // Uncompressed
    "CFHD",                                            // Cineform
    "mjp2"                                             // JPEG 2000
]

/// Checks if a codec is intra-only (all I-frames)
public func isIntraOnlyCodec(_ codecType: FourCharCode) -> Bool {
    let codecID = fourCCToString(codecType)
    return intraOnlyCodecFourCCs.contains(codecID)
}

/// Checks if codec supports NAL-based frame type detection
public func supportsNALFrameTypeDetection(_ codecType: FourCharCode) -> Bool {
    let codecID = fourCCToString(codecType).lowercased()
    return codecID.hasPrefix("avc") || codecID == "h264" ||
           codecID.hasPrefix("hev") || codecID.hasPrefix("hvc") || codecID == "hevc"
}

// MARK: - Sample Attachment Detection

/// Detects frame type from CMSampleBuffer attachments (sdtp box info).
/// Uses dependency information when available.
///
/// Sample Dependency Type (sdtp) box provides:
/// - kCMSampleAttachmentKey_DependsOnOthers: true = non-I-frame
/// - kCMSampleAttachmentKey_IsDependedOnByOthers: true = P-frame (others depend on it), false = B-frame (droppable)
public func detectFrameTypeFromAttachments(_ sampleBuffer: CMSampleBuffer) -> FrameType? {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
          CFArrayGetCount(attachments) > 0,
          let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self) as? [CFString: Any] else {
        return nil
    }
    
    // Check sync sample first
    let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
    if !notSync {
        return .i  // Sync sample = I-frame
    }
    
    // Check dependency info from sdtp box
    if let dependsOnOthers = dict[kCMSampleAttachmentKey_DependsOnOthers] as? Bool {
        if !dependsOnOthers {
            return .i  // Doesn't depend on others = I-frame
        }
        
        // Check if other frames depend on this one
        if let isDependedOn = dict[kCMSampleAttachmentKey_IsDependedOnByOthers] as? Bool {
            if isDependedOn {
                return .p  // Others depend on this = P-frame
            } else {
                return .b  // Droppable frame = B-frame
            }
        }
    }
    
    return nil  // Insufficient info
}
