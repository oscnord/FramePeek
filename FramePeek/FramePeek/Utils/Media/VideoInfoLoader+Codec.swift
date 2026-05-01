import Foundation
import AVFoundation
import CoreMedia

public struct CodecInfo {
    public let codec: String
    public let codecIdRaw: String?
    public let codecProfile: String?
    public let codecIdInfo: String?
    public let chromaSubsampling: String?
    public let hasDolbyVision: Bool
    public let maxBitrate: String?
    
    public init(codec: String, codecIdRaw: String?, codecProfile: String?, codecIdInfo: String?, chromaSubsampling: String?, hasDolbyVision: Bool, maxBitrate: String?) {
        self.codec = codec
        self.codecIdRaw = codecIdRaw
        self.codecProfile = codecProfile
        self.codecIdInfo = codecIdInfo
        self.chromaSubsampling = chromaSubsampling
        self.hasDolbyVision = hasDolbyVision
        self.maxBitrate = maxBitrate
    }
}

public func extractCodecInfo(videoTrack: AVAssetTrack) async -> CodecInfo? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else { return nil }

        // Codec
        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
        let codecID = fourCCToString(codecType)
        let codecIdRaw = codecID.trimmingCharacters(in: .whitespaces)
        let codec = videoCodecName(codecID)
        let codecIdInfo = videoCodecInfo(codecID)

        var codecProfile: String?
        var chromaSubsampling: String?
        var hasDolbyVision = false
        var maxBitrate: String?

        if let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] {
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
                    // Try to extract max bitrate from HEVC config
                    maxBitrate = parseHEVCMaxBitrate(hvcCData)
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
                    // Try to extract max bitrate from AVC config
                    if maxBitrate == nil {
                        maxBitrate = parseAVCMaxBitrate(avcCData)
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
            }
        }

        return CodecInfo(
            codec: codec,
            codecIdRaw: codecIdRaw,
            codecProfile: codecProfile,
            codecIdInfo: codecIdInfo,
            chromaSubsampling: chromaSubsampling,
            hasDolbyVision: hasDolbyVision,
            maxBitrate: maxBitrate
        )
    } catch {
        Log.media.error("Error extracting codec info: \(error.localizedDescription)")
        return nil
    }
}
