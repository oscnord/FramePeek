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

enum BitrateVisualizationMode: String, CaseIterable, Identifiable {
    case second = "Second"    // 1-second rolling window (default)
    case frame = "Frame"      // Per-frame bitrate
    case gop = "GOP"          // Per-GOP (Group of Pictures) bitrate
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .second: return "Second"
        case .frame: return "Frame"
        case .gop: return "GOP"
        }
    }
}

struct FrameSamplingOptions {
    let minEmitIntervalSeconds: Double?
    let maxSamples: Int
    let emitEveryNSamples: Int
    let preferAccuracy: Bool  // If true, uses reader path (accurate) instead of cursor path (fast)
    let visualizationMode: BitrateVisualizationMode  // How to aggregate bitrate samples

    init(
        minEmitIntervalSeconds: Double?,
        maxSamples: Int,
        emitEveryNSamples: Int,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second
    ) {
        self.minEmitIntervalSeconds = minEmitIntervalSeconds
        self.maxSamples = maxSamples
        self.emitEveryNSamples = emitEveryNSamples
        self.preferAccuracy = preferAccuracy
        self.visualizationMode = visualizationMode
    }

    static func everyFrame(
        maxSamples: Int = 2000,
        emitEveryNSamples: Int = 100,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second
    ) -> Self {
        .init(
            minEmitIntervalSeconds: nil,
            maxSamples: maxSamples,
            emitEveryNSamples: emitEveryNSamples,
            preferAccuracy: preferAccuracy,
            visualizationMode: visualizationMode
        )
    }

    static func interval(
        _ seconds: Double,
        maxSamples: Int = 2000,
        emitEveryNSamples: Int = 100,
        preferAccuracy: Bool = false,
        visualizationMode: BitrateVisualizationMode = .second
    ) -> Self {
        .init(
            minEmitIntervalSeconds: max(0, seconds),
            maxSamples: maxSamples,
            emitEveryNSamples: emitEveryNSamples,
            preferAccuracy: preferAccuracy,
            visualizationMode: visualizationMode
        )
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
