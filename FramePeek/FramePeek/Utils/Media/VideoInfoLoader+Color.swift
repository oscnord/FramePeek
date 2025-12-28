//
//  VideoInfoLoader+Color.swift
//  FramePeek
//
//  Created by Oscar Nord on 2025-12-06.
//

import Foundation
import AVFoundation
import CoreMedia

struct ColorInfo {
    let colorSpace: String?
    let chromaSubsampling: String?
    let colorPrimaries: String?
    let transferFunction: String?
    let matrixCoefficients: String?
    let colorRange: String?
    let inferredBitDepthBpc: Int?
    let hdrFormat: String?
}

func extractColorInfo(videoTrack: AVAssetTrack, hasDolbyVision: Bool) async -> ColorInfo? {
    do {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first,
              let extDict = CMFormatDescriptionGetExtensions(formatDesc) as? [CFString: Any] else {
            return nil
        }
        
        var colorSpace: String? = nil
        var chromaSubsampling: String? = nil
        var colorPrimaries: String? = nil
        var transferFunction: String? = nil
        var matrixCoefficients: String? = nil
        var colorRange: String? = nil
        var inferredBitDepthBpc: Int? = nil
        
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
        print("Error extracting color info: \(error.localizedDescription)")
        return nil
    }
}


