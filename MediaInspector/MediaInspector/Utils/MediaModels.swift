//
//  MediaModels.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import Foundation

// MARK: - Audio Track Info

struct AudioTrackInfo {
    let index: Int
    let codec: String
    let codecDisplayName: String
    let channels: Int
    let channelLayout: String
    let sampleRateHz: Double
    let bitrateKbps: Float?
    let languageCode: String?
}

// MARK: - Extended Video Info

struct ExtendedVideoInfo {
    // File / Container
    let fileName: String
    let fileSize: String
    let fileSizeBytes: UInt64?
    let overallBitrate: String
    let duration: String
    let durationFormatted: String
    let containerFormat: String?
    let containerFormatProfile: String?
    let codecIdRaw: String?
    
    // Video basic
    let resolution: String
    let displayAspectRatio: String?
    let frameRate: String
    let codec: String
    let codecProfile: String?
    let codecIdInfo: String?
    
    // Video extra
    let orientationDegrees: Int?
    let trackBitrate: String?
    let maxBitrate: String?
    let pixelAspectRatio: String?
    let cleanAperture: String?
    let scanType: String?
    let frameRateMode: String?
    let colorSpace: String?
    let chromaSubsampling: String?
    let bitsPerPixelFrame: String?
    let videoStreamSize: String?
    
    // Color
    let colorPrimaries: String?
    let transferFunction: String?
    let matrixCoefficients: String?
    let colorRange: String?
    let bitDepth: String?
    let hdrFormat: String?
    
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

// MARK: - Frame Analysis

struct FrameAnalysisResult {
    let samples: [BitrateSample]
    let averageFPS: Double?
    let minInterval: Double?
    let maxInterval: Double?
}

struct FrameSamplingOptions {
    let minEmitIntervalSeconds: Double?
    let maxSamples: Int
    let emitEveryNSamples: Int

    static func everyFrame(maxSamples: Int = 2000, emitEveryNSamples: Int = 100) -> Self {
        .init(minEmitIntervalSeconds: nil, maxSamples: maxSamples, emitEveryNSamples: emitEveryNSamples)
    }

    static func interval(_ seconds: Double, maxSamples: Int = 2000, emitEveryNSamples: Int = 100) -> Self {
        .init(minEmitIntervalSeconds: max(0, seconds), maxSamples: maxSamples, emitEveryNSamples: emitEveryNSamples)
    }
}

// MARK: - AV1 Config

struct AV1ConfigSummary {
    let profile: Int
    let level: Int
    let bitDepth: Int
    let chromaSubsampling: String
    let fullRange: Bool
}
