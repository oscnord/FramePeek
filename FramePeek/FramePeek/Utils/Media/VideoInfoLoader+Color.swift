import Foundation
import AVFoundation
import CoreMedia

public struct ColorInfo {
    public let colorSpace: String?
    public let chromaSubsampling: String?
    public let colorPrimaries: String?
    public let transferFunction: String?
    public let matrixCoefficients: String?
    public let colorRange: String?
    public let inferredBitDepthBpc: Int?
    public let hdrFormat: String?
    
    public init(colorSpace: String?, chromaSubsampling: String?, colorPrimaries: String?, transferFunction: String?, matrixCoefficients: String?, colorRange: String?, inferredBitDepthBpc: Int?, hdrFormat: String?) {
        self.colorSpace = colorSpace
        self.chromaSubsampling = chromaSubsampling
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.matrixCoefficients = matrixCoefficients
        self.colorRange = colorRange
        self.inferredBitDepthBpc = inferredBitDepthBpc
        self.hdrFormat = hdrFormat
    }
}

public func extractColorInfo(videoTrack: AVAssetTrack, hasDolbyVision: Bool) async -> ColorInfo? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] else {
            return nil
        }

        var colorSpace: String?
        var chromaSubsampling: String?
        var colorPrimaries: String?
        var transferFunction: String?
        var matrixCoefficients: String?
        var colorRange: String?
        var inferredBitDepthBpc: Int?

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

        // Detect HDR format
        let hdrFormat = detectHDRFormat(
            transferFunction: transferFunction,
            colorPrimaries: colorPrimaries,
            hasDolbyVisionConfig: hasDolbyVision
        )

        return ColorInfo(
            colorSpace: colorSpace,
            chromaSubsampling: chromaSubsampling,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            matrixCoefficients: matrixCoefficients,
            colorRange: colorRange,
            inferredBitDepthBpc: inferredBitDepthBpc,
            hdrFormat: hdrFormat
        )
    } catch {
        Log.media.error("Error extracting color info: \(error.localizedDescription)")
        return nil
    }
}
