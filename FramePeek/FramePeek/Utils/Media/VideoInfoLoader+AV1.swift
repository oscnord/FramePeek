import Foundation
import AVFoundation
import CoreMedia

public struct AV1Info {
    public let av1CSize: Int?
    public let av1Profile: String?
    public let av1Level: String?
    public let av1Chroma: String?
    public let av1Range: String?
    public let inferredBitDepthBpc: Int?
    public let chromaSubsampling: String?
    
    public init(av1CSize: Int?, av1Profile: String?, av1Level: String?, av1Chroma: String?, av1Range: String?, inferredBitDepthBpc: Int?, chromaSubsampling: String?) {
        self.av1CSize = av1CSize
        self.av1Profile = av1Profile
        self.av1Level = av1Level
        self.av1Chroma = av1Chroma
        self.av1Range = av1Range
        self.inferredBitDepthBpc = inferredBitDepthBpc
        self.chromaSubsampling = chromaSubsampling
    }
}

public func extractAV1Info(videoTrack: AVAssetTrack) async -> AV1Info? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any],
              let atoms = extDict[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [CFString: Any],
              let av1CData = atoms["av1C" as CFString] as? Data else {
            return nil
        }

        let av1CSize = av1CData.count
        var av1Profile: String?
        var av1Level: String?
        var av1Chroma: String?
        var av1Range: String?
        var inferredBitDepthBpc: Int?
        var chromaSubsampling: String?

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
