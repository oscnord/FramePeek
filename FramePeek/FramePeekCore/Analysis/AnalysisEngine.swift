import Foundation
import AVFoundation

// MARK: - Analysis Options

/// Configuration options for running analysis
public struct AnalysisOptions: Codable, Sendable {
    // What to analyze
    public var includeMetadata: Bool
    public var includeBitrate: Bool
    public var includeGOP: Bool
    public var includeWaveform: Bool
    public var includeSync: Bool
    public var includeColor: Bool
    public var includeKeyframes: Bool
    public var includeThumbnails: Bool
    
    // Bitrate options
    public var bitrateMode: BitrateVisualizationMode
    public var preferAccuracy: Bool
    public var maxSamples: Int
    
    // GOP options
    public var gopDetectFrameTypes: Bool
    public var gopMaxScanSeconds: Double?
    public var gopStatsOnly: Bool
    
    // Thumbnail options
    public var thumbnailCount: Int
    public var thumbnailSize: ThumbnailSize
    public var thumbnailOutputDirectory: URL?
    
    public init(
        includeMetadata: Bool = true,
        includeBitrate: Bool = false,
        includeGOP: Bool = false,
        includeWaveform: Bool = false,
        includeSync: Bool = false,
        includeColor: Bool = false,
        includeKeyframes: Bool = false,
        includeThumbnails: Bool = false,
        bitrateMode: BitrateVisualizationMode = .second,
        preferAccuracy: Bool = false,
        maxSamples: Int = 2000,
        gopDetectFrameTypes: Bool = true,
        gopMaxScanSeconds: Double? = nil,
        gopStatsOnly: Bool = false,
        thumbnailCount: Int = 10,
        thumbnailSize: ThumbnailSize = .medium,
        thumbnailOutputDirectory: URL? = nil
    ) {
        self.includeMetadata = includeMetadata
        self.includeBitrate = includeBitrate
        self.includeGOP = includeGOP
        self.includeWaveform = includeWaveform
        self.includeSync = includeSync
        self.includeColor = includeColor
        self.includeKeyframes = includeKeyframes
        self.includeThumbnails = includeThumbnails
        self.bitrateMode = bitrateMode
        self.preferAccuracy = preferAccuracy
        self.maxSamples = maxSamples
        self.gopDetectFrameTypes = gopDetectFrameTypes
        self.gopMaxScanSeconds = gopMaxScanSeconds
        self.gopStatsOnly = gopStatsOnly
        self.thumbnailCount = thumbnailCount
        self.thumbnailSize = thumbnailSize
        self.thumbnailOutputDirectory = thumbnailOutputDirectory
    }
    
    /// Convenience initializer for metadata-only analysis
    public static var metadataOnly: AnalysisOptions {
        AnalysisOptions(includeMetadata: true)
    }
    
    /// Convenience initializer for full analysis
    public static var all: AnalysisOptions {
        AnalysisOptions(
            includeMetadata: true,
            includeBitrate: true,
            includeGOP: true,
            includeWaveform: true,
            includeSync: true,
            includeColor: false, // Color analysis is expensive, opt-in
            includeKeyframes: true,
            includeThumbnails: false
        )
    }
}

// MARK: - Analysis Progress

/// Represents the current state of analysis
public enum AnalysisPhase: String, Codable, CaseIterable, Sendable {
    case metadata
    case bitrate
    case gop
    case waveform
    case sync
    case color
    case thumbnails
    
    public var displayName: String {
        switch self {
        case .metadata: return "Metadata"
        case .bitrate: return "Bitrate Analysis"
        case .gop: return "GOP Analysis"
        case .waveform: return "Waveform Extraction"
        case .sync: return "A/V Sync Analysis"
        case .color: return "Color Analysis"
        case .thumbnails: return "Thumbnail Generation"
        }
    }
}

/// Progress update during analysis
public enum AnalysisProgress: Sendable {
    case started(phase: AnalysisPhase)
    case progress(phase: AnalysisPhase, percent: Double, message: String?)
    case phaseComplete(phase: AnalysisPhase)
    case complete(result: AnalysisResult)
    case failed(phase: AnalysisPhase?, error: Error)
    
    public var isComplete: Bool {
        switch self {
        case .complete, .failed: return true
        default: return false
        }
    }
}

// MARK: - Analysis Error

/// Errors that can occur during analysis
public enum AnalysisError: Error, LocalizedError {
    case fileNotFound(URL)
    case invalidMediaFile(URL)
    case noVideoTrack
    case noAudioTrack
    case cancelled
    case analysisError(phase: AnalysisPhase, underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .invalidMediaFile(let url):
            return "Invalid media file: \(url.lastPathComponent)"
        case .noVideoTrack:
            return "No video track found in file"
        case .noAudioTrack:
            return "No audio track found in file"
        case .cancelled:
            return "Analysis was cancelled"
        case .analysisError(let phase, let error):
            return "\(phase.displayName) failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Analysis Engine

/// Main entry point for running media analysis.
///
/// Use this actor to analyze media files programmatically.
/// Provides both single-shot and streaming APIs.
///
/// The analyzer source files (`getExtendedInfo`, `extractBitratesFast`,
/// `extractGOPSegmentsFast`, `extractWaveformFast`, `analyzeAudioVideoSync`,
/// `SyncSampleParser`) physically live under `FramePeek/Utils/` but compile
/// into the `FramePeekCore` framework target via `membershipExceptions` in
/// `project.pbxproj`. Both this engine and the CLI consume them via the
/// `FramePeekCore` framework.
///
/// Example usage:
/// ```swift
/// let engine = AnalysisEngine()
/// let options = AnalysisOptions(includeMetadata: true, includeBitrate: true)
/// let result = try await engine.analyze(url: fileURL, options: options)
/// ```
public actor AnalysisEngine {
    
    private var currentTask: Task<Void, Never>?
    
    public init() {}
    
    /// Cancels any in-progress analysis
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    /// Performs analysis and returns the complete result
    /// - Parameters:
    ///   - url: URL of the media file to analyze
    ///   - options: Analysis options specifying what to analyze
    /// - Returns: Complete analysis result
    /// - Throws: AnalysisError if analysis fails
    public func analyze(url: URL, options: AnalysisOptions) async throws -> AnalysisResult {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AnalysisError.fileNotFound(url)
        }
        
        // Create asset
        let asset = AVURLAsset(url: url)
        
        // Verify it's a valid media file
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw AnalysisError.invalidMediaFile(url)
        }
        
        let fileInfo = FileInfo(url: url)
        
        // Run analyses based on options
        var metadata: ExtendedVideoInfo?
        var bitrateOutput: BitrateAnalysisOutput?
        var gopOutput: GOPAnalysisOutput?
        var waveforms: [String: [WaveformSampleOutput]]?
        var syncOutput: SyncAnalysisOutput?
        let colorSummary: ColorAnalysisSummary? = nil
        var keyframes: [KeyframeOutput]?
        let thumbnails: [ThumbnailOutput]? = nil
        
        // Metadata (always fast, usually always wanted)
        if options.includeMetadata {
            metadata = await extractMetadata(url: url, asset: asset)
        }
        
        // Bitrate analysis
        if options.includeBitrate {
            let samples = await extractBitrate(asset: asset, options: options)
            let stats = BitrateStats(samples: samples)
            bitrateOutput = BitrateAnalysisOutput(
                mode: options.bitrateMode,
                stats: stats,
                samples: samples.map { BitrateSampleOutput(sample: $0) }
            )
        }
        
        // GOP analysis
        if options.includeGOP {
            let gopResult = await extractGOP(asset: asset, url: url, options: options)
            gopOutput = GOPAnalysisOutput(result: gopResult, includeSegments: !options.gopStatsOnly)
        }
        
        // Waveform extraction
        if options.includeWaveform {
            waveforms = await extractWaveforms(asset: asset, maxSamples: options.maxSamples)
        }
        
        // Keyframe extraction
        if options.includeKeyframes {
            keyframes = await extractKeyframes(url: url)
        }
        
        // Sync analysis
        if options.includeSync {
            if let syncResult = await extractSync(asset: asset) {
                syncOutput = SyncAnalysisOutput(result: syncResult)
            }
        }
        
        // Note: Color analysis and thumbnails would need additional integration
        
        return AnalysisResult(
            file: fileInfo,
            metadata: metadata,
            bitrate: bitrateOutput,
            gop: gopOutput,
            waveforms: waveforms,
            sync: syncOutput,
            color: colorSummary,
            keyframes: keyframes,
            thumbnails: thumbnails
        )
    }
    
    /// Performs analysis with progress updates via AsyncStream
    /// - Parameters:
    ///   - url: URL of the media file to analyze
    ///   - options: Analysis options specifying what to analyze
    /// - Returns: AsyncStream of progress updates, ending with complete or failed
    public func analyzeWithProgress(url: URL, options: AnalysisOptions) -> AsyncStream<AnalysisProgress> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let result = try await analyze(url: url, options: options)
                    continuation.yield(.complete(result: result))
                } catch {
                    if let analysisError = error as? AnalysisError {
                        continuation.yield(.failed(phase: nil, error: analysisError))
                    } else {
                        continuation.yield(.failed(phase: nil, error: error))
                    }
                }
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    // MARK: - Private Analysis Methods
    
    private func extractMetadata(url: URL, asset: AVAsset) async -> ExtendedVideoInfo? {
        // Call the actual getExtendedInfo function from VideoInfoLoader
        // This requires VideoInfoLoader.swift to be in FramePeekCore target
        return await getExtendedInfo(url: url, asset: asset)
    }
    
    private func extractBitrate(asset: AVAsset, options: AnalysisOptions) async -> [BitrateSample] {
        // Build frame sampling options from analysis options
        let samplingOptions = FrameSamplingOptions(
            minEmitIntervalSeconds: 0.1,
            maxSamples: options.maxSamples,
            emitEveryNSamples: 100,
            preferAccuracy: options.preferAccuracy,
            visualizationMode: options.bitrateMode
        )
        
        // Collect all samples from the async stream
        var allSamples: [BitrateSample] = []
        let stream = extractBitratesFast(asset: asset, options: samplingOptions)
        
        for await update in stream {
            allSamples.append(contentsOf: update.appendedSamples)
            if update.isFinished {
                break
            }
        }
        
        return allSamples
    }
    
    private func extractGOP(asset: AVAsset, url: URL, options: AnalysisOptions) async -> GOPAnalysisResult {
        // Build GOP options from analysis options
        let gopOptions = GOPOptions(
            maxScanSeconds: options.gopMaxScanSeconds,
            maxGOPs: nil,
            emitEveryNGOPs: 25,
            detectFrameTypes: options.gopDetectFrameTypes
        )
        
        // Collect all segments from the async stream
        var segments: [GOPSegment] = []
        var isPreview = false
        var scannedUntil: Double = 0
        var structureType: GOPStructureType = .unknown
        
        let stream = extractGOPSegmentsFast(asset: asset, url: url, options: gopOptions)
        
        for await update in stream {
            segments.append(contentsOf: update.appendedSegments)
            isPreview = update.isPreview
            scannedUntil = update.scannedUntilSeconds
            structureType = update.structureType
            if update.isFinished {
                break
            }
        }
        
        return GOPAnalysisResult(
            segments: segments,
            isPreview: isPreview,
            scannedUntilSeconds: scannedUntil,
            isFinished: true,
            structureType: structureType
        )
    }
    
    private func extractWaveforms(asset: AVAsset, maxSamples: Int) async -> [String: [WaveformSampleOutput]] {
        var waveforms: [String: [WaveformSampleOutput]] = [:]
        
        // Get audio tracks
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio) else {
            return waveforms
        }
        
        // Get duration for waveform extraction
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration > 0 else { return waveforms }
        
        // Extract waveform for each audio track
        for (index, audioTrack) in audioTracks.enumerated() {
            var samples: [WaveformSampleOutput] = []
            let stream = extractWaveformFast(
                asset: asset,
                audioTrack: audioTrack,
                durationSeconds: duration,
                maxSamples: maxSamples
            )
            
            for await update in stream {
                let outputSamples = update.appendedSamples.map { WaveformSampleOutput(sample: $0) }
                samples.append(contentsOf: outputSamples)
                if update.isFinished {
                    break
                }
            }
            
            waveforms["\(index)"] = samples
        }
        
        return waveforms
    }
    
    private func extractSync(asset: AVAsset) async -> SyncAnalysisResult? {
        // Call the actual analyzeAudioVideoSync function
        return await analyzeAudioVideoSync(asset: asset)
    }
    
    private func extractKeyframes(url: URL) async -> [KeyframeOutput] {
        // Use SyncSampleParser to get keyframe timestamps
        guard SyncSampleParser.canUseFastParsing(for: url),
              let syncResult = await SyncSampleParser.parseSyncSamples(from: url) else {
            return []
        }
        
        let keyframeMarkers = SyncSampleParser.keyframeTimestamps(from: syncResult)
        return keyframeMarkers.enumerated().map { index, marker in
            KeyframeOutput(time: marker.timestamp, index: index)
        }
    }
}
