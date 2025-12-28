//
//  VideoInfoLoader+Codec.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

struct CodecInfo {
    let codec: String
    let codecIdRaw: String?
    let codecProfile: String?
    let codecIdInfo: String?
    let chromaSubsampling: String?
    let hasDolbyVision: Bool
    let maxBitrate: String?
}

func extractCodecInfo(videoTrack: AVAssetTrack) async -> CodecInfo? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else { return nil }
        
        // Codec
        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
        let codecID = fourCCToString(codecType)
        let codecIdRaw = codecID.trimmingCharacters(in: .whitespaces)
        let codec = videoCodecName(codecID)
        let codecIdInfo = videoCodecInfo(codecID)
        
        var codecProfile: String? = nil
        var chromaSubsampling: String? = nil
        var hasDolbyVision = false
        var maxBitrate: String? = nil
        
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
        print("Error extracting codec info: \(error.localizedDescription)")
        return nil
    }
}


