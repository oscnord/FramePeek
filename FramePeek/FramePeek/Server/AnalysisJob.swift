//
//  AnalysisJob.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import FramePeekCore

// MARK: - Job Status

/// Status of an analysis job
public enum JobStatus: String, Codable, Sendable {
    case pending
    case processing
    case complete
    case failed
    case cancelled
}

// MARK: - Job Phase Status

/// Status of individual analysis phases within a job
public enum JobPhaseStatus: String, Codable, Sendable {
    case pending
    case processing
    case complete
    case skipped
    case failed
}

// MARK: - Analysis Job

/// Represents a single analysis job in the queue
public struct AnalysisJob: Identifiable, Sendable {
    public let id: String
    public let fileURL: URL
    public let fileName: String
    public let options: AnalysisOptions
    public let createdAt: Date
    public let source: JobSource
    public let webhook: WebhookConfig?
    
    public var status: JobStatus
    public var progress: Double
    public var currentPhase: AnalysisPhase?
    public var phaseStatuses: [AnalysisPhase: JobPhaseStatus]
    public var startedAt: Date?
    public var completedAt: Date?
    public var result: AnalysisResult?
    public var error: String?
    
    public init(
        id: String = UUID().uuidString,
        fileURL: URL,
        options: AnalysisOptions,
        source: JobSource = .api,
        webhook: WebhookConfig? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.options = options
        self.createdAt = Date()
        self.source = source
        self.webhook = webhook
        self.status = .pending
        self.progress = 0
        self.currentPhase = nil
        self.phaseStatuses = Self.initialPhaseStatuses(for: options)
        self.startedAt = nil
        self.completedAt = nil
        self.result = nil
        self.error = nil
    }
    
    /// Creates initial phase statuses based on options
    private static func initialPhaseStatuses(for options: AnalysisOptions) -> [AnalysisPhase: JobPhaseStatus] {
        var statuses: [AnalysisPhase: JobPhaseStatus] = [:]
        
        statuses[.metadata] = options.includeMetadata ? .pending : .skipped
        statuses[.bitrate] = options.includeBitrate ? .pending : .skipped
        statuses[.gop] = options.includeGOP ? .pending : .skipped
        statuses[.waveform] = options.includeWaveform ? .pending : .skipped
        statuses[.sync] = options.includeSync ? .pending : .skipped
        statuses[.color] = options.includeColor ? .pending : .skipped
        statuses[.thumbnails] = options.includeThumbnails ? .pending : .skipped
        
        return statuses
    }
    
    /// Duration of the job (if completed or in progress)
    public var duration: TimeInterval? {
        guard let started = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(started)
    }
    
    /// Formatted duration string
    public var durationFormatted: String? {
        guard let duration = duration else { return nil }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Job Source

/// Where the job originated from
public enum JobSource: String, Codable, Sendable {
    case api           // REST API request
    case upload        // File upload via API
    case gui           // Started from GUI
}

// MARK: - Completed Job (for history)

/// A completed job stored in history
public struct CompletedJob: Identifiable, Codable, Sendable {
    public let id: String
    public let fileName: String
    public let filePath: String
    public let source: JobSource
    public let createdAt: Date
    public let completedAt: Date
    public let duration: TimeInterval
    public let status: JobStatus
    public let error: String?
    public let resultJSON: Data?  // Stored as JSON data to save memory
    
    public init(from job: AnalysisJob) {
        self.id = job.id
        self.fileName = job.fileName
        self.filePath = job.fileURL.path
        self.source = job.source
        self.createdAt = job.createdAt
        self.completedAt = job.completedAt ?? Date()
        self.duration = job.duration ?? 0
        self.status = job.status
        self.error = job.error
        
        // Encode result to JSON data
        if let result = job.result {
            self.resultJSON = try? JSONEncoder().encode(result)
        } else {
            self.resultJSON = nil
        }
    }
    
    /// Decode the stored result
    public func decodeResult() -> AnalysisResult? {
        guard let data = resultJSON else { return nil }
        return try? JSONDecoder().decode(AnalysisResult.self, from: data)
    }
    
    /// Formatted duration string
    public var durationFormatted: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
    
    /// Relative time string (e.g., "5 min ago")
    public var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: completedAt, relativeTo: Date())
    }
}

// MARK: - API Response Models

/// Response for job status endpoint
public struct JobStatusResponse: Codable, Sendable {
    public let id: String
    public let status: JobStatus
    public let progress: Double
    public let currentPhase: String?
    public let phases: [String: String]
    public let createdAt: Date
    public let startedAt: Date?
    public let completedAt: Date?
    public let error: String?
    public let result: AnalysisResult?
    
    public init(from job: AnalysisJob) {
        self.id = job.id
        self.status = job.status
        self.progress = job.progress
        self.currentPhase = job.currentPhase?.rawValue
        self.phases = Dictionary(uniqueKeysWithValues: job.phaseStatuses.map { ($0.key.rawValue, $0.value.rawValue) })
        self.createdAt = job.createdAt
        self.startedAt = job.startedAt
        self.completedAt = job.completedAt
        self.error = job.error
        self.result = job.status == .complete ? job.result : nil
    }
}

/// Response for job list endpoint
public struct JobListResponse: Codable, Sendable {
    public let activeJobs: [JobSummary]
    public let recentJobs: [JobSummary]
    
    public struct JobSummary: Codable, Sendable {
        public let id: String
        public let fileName: String
        public let status: JobStatus
        public let progress: Double
        public let createdAt: Date
        public let completedAt: Date?
    }
}

/// Request body for analyze/path endpoint
public struct AnalyzePathRequest: Codable, Sendable {
    public let path: String
    public let options: AnalyzeOptions?
    public let webhook: WebhookConfig?
    
    public struct AnalyzeOptions: Codable, Sendable {
        public var all: Bool?
        public var info: Bool?
        public var bitrate: Bool?
        public var gop: Bool?
        public var waveform: Bool?
        public var sync: Bool?
        public var color: Bool?
        public var keyframes: Bool?
        public var thumbnails: Bool?
        public var bitrateMode: String?
        public var maxSamples: Int?
        public var gopFrameTypes: Bool?
        public var gopMaxSeconds: Double?
        
        /// Convert to FramePeekCore AnalysisOptions
        public func toAnalysisOptions() -> AnalysisOptions {
            let runAll = all ?? false
            let runInfo = info ?? (!runAll && bitrate != true && gop != true && waveform != true && sync != true && color != true && keyframes != true && thumbnails != true)
            
            var mode: BitrateVisualizationMode = .second
            if let modeStr = bitrateMode {
                switch modeStr {
                case "frame": mode = .frame
                case "gop": mode = .gop
                default: mode = .second
                }
            }
            
            return AnalysisOptions(
                includeMetadata: runAll || runInfo,
                includeBitrate: runAll || (bitrate ?? false),
                includeGOP: runAll || (gop ?? false),
                includeWaveform: runAll || (waveform ?? false),
                includeSync: runAll || (sync ?? false),
                includeColor: runAll || (color ?? false),
                includeKeyframes: runAll || (keyframes ?? false),
                includeThumbnails: thumbnails ?? false,
                bitrateMode: mode,
                maxSamples: maxSamples ?? 2000,
                gopDetectFrameTypes: gopFrameTypes ?? true,
                gopMaxScanSeconds: gopMaxSeconds
            )
        }
    }
}

/// Response when job is created
public struct JobCreatedResponse: Codable, Sendable {
    public let id: String
    public let status: JobStatus
    public let message: String
    
    public init(job: AnalysisJob) {
        self.id = job.id
        self.status = job.status
        self.message = "Job created successfully"
    }
}
