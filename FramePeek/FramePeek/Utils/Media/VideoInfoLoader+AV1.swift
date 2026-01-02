import Foundation
import AVFoundation
import CoreMedia

struct AV1Info {
    let av1CSize: Int?
    let av1Profile: String?
    let av1Level: String?
    let av1Chroma: String?
    let av1Range: String?
    let inferredBitDepthBpc: Int?
    let chromaSubsampling: String?
}

func extractAV1Info(videoTrack: AVAssetTrack) async -> AV1Info? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any],
              let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any],
              let av1CData = atoms["av1C" as CFString] as? Data else {
            return nil
        }
        
        let av1CSize = av1CData.count
        var av1Profile: String? = nil
        var av1Level: String? = nil
        var av1Chroma: String? = nil
        var av1Range: String? = nil
        var inferredBitDepthBpc: Int? = nil
        var chromaSubsampling: String? = nil
        
        if let cfg = parseAV1C(av1CData) {
            av1Profile = "Profile \(cfg.profile)"
            av1Level = "Level \(cfg.level)"
            av1Chroma = cfg.chromaSubsampling
            chromaSubsampling = cfg.chromaSubsampling
            av1Range = cfg.fullRange ? "Full" : "Limited"
            inferredBitDepthBpc = cfg.bitDepth
        }
        
        return AV1Info(
            av1CSize: av1CSize,
            av1Profile: av1Profile,
            av1Level: av1Level,
            av1Chroma: av1Chroma,
            av1Range: av1Range,
            inferredBitDepthBpc: inferredBitDepthBpc,
            chromaSubsampling: chromaSubsampling
        )
    } catch {
        print("Error extracting AV1 info: \(error.localizedDescription)")
        return nil
    }
}



