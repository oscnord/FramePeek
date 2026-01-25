//
//  WebhookService.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import FramePeekCore

// MARK: - Webhook Configuration

/// Configuration for webhook callbacks
public struct WebhookConfig: Codable, Sendable {
    public let url: String
    public let headers: [String: String]?
    
    public init(url: String, headers: [String: String]? = nil) {
        self.url = url
        self.headers = headers
    }
}

// MARK: - Webhook Payload

/// Payload sent to webhook endpoints
public struct WebhookPayload: Codable, Sendable {
    public let event: String              // "job.completed" or "job.failed"
    public let jobId: String
    public let status: JobStatus
    public let duration: TimeInterval
    public let result: TruncatedAnalysisResult?
    public let truncated: [String]?       // Fields that were truncated
    public let resultUrl: String          // Full result endpoint
    public let error: String?
    
    public init(
        event: String,
        jobId: String,
        status: JobStatus,
        duration: TimeInterval,
        result: TruncatedAnalysisResult?,
        truncated: [String]?,
        resultUrl: String,
        error: String?
    ) {
        self.event = event
        self.jobId = jobId
        self.status = status
        self.duration = duration
        self.result = result
        self.truncated = truncated
        self.resultUrl = resultUrl
        self.error = error
    }
}

// MARK: - Truncated Analysis Result

/// Analysis result with potentially truncated large arrays
public struct TruncatedAnalysisResult: Codable, Sendable {
    public let metadata: ExtendedVideoInfo?
    public let bitrate: TruncatedBitrateResult?
    public let gop: GOPAnalysisOutput?
    public let waveforms: [String: [WaveformSampleOutput]]?
    public let sync: SyncAnalysisOutput?
    public let keyframes: [KeyframeOutput]?
    
    public init(
        metadata: ExtendedVideoInfo?,
        bitrate: TruncatedBitrateResult?,
        gop: GOPAnalysisOutput?,
        waveforms: [String: [WaveformSampleOutput]]?,
        sync: SyncAnalysisOutput?,
        keyframes: [KeyframeOutput]?
    ) {
        self.metadata = metadata
        self.bitrate = bitrate
        self.gop = gop
        self.waveforms = waveforms
        self.sync = sync
        self.keyframes = keyframes
    }
}

/// Bitrate result with potentially truncated samples
public struct TruncatedBitrateResult: Codable, Sendable {
    public let mode: String
    public let samples: [BitrateSampleOutput]?  // nil if truncated
    public let sampleCount: Int
    public let statistics: BitrateStatistics?
    
    public init(mode: String, samples: [BitrateSampleOutput]?, sampleCount: Int, statistics: BitrateStatistics?) {
        self.mode = mode
        self.samples = samples
        self.sampleCount = sampleCount
        self.statistics = statistics
    }
}

/// Basic bitrate statistics
public struct BitrateStatistics: Codable, Sendable {
    public let average: Double
    public let max: Double
    public let min: Double
    
    public init(average: Double, max: Double, min: Double) {
        self.average = average
        self.max = max
        self.min = min
    }
}

// MARK: - Delivery Result

/// Result of a webhook delivery attempt
public struct WebhookDeliveryResult: Sendable {
    public let success: Bool
    public let attempts: Int
    public let statusCode: Int?
    public let error: String?
    
    public init(success: Bool, attempts: Int, statusCode: Int?, error: String?) {
        self.success = success
        self.attempts = attempts
        self.statusCode = statusCode
        self.error = error
    }
}

// MARK: - Webhook Service

/// Actor handling webhook delivery with retry logic
public actor WebhookService {
    
    // MARK: - Singleton
    
    public static let shared = WebhookService()
    
    // MARK: - Configuration
    
    public let maxRetries = 3
    public let timeout: TimeInterval = 30
    public let initialDelay: TimeInterval = 1.0
    public let backoffFactor: Double = 2.0
    public let maxPayloadSize = 1_048_576  // 1MB
    
    // Truncation thresholds
    public let maxBitrateSamples = 1000
    public let maxWaveformSamples = 1000
    public let maxKeyframes = 500
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Send a webhook with retry logic
    public func send(config: WebhookConfig, payload: WebhookPayload) async -> WebhookDeliveryResult {
        guard let url = URL(string: config.url) else {
            return WebhookDeliveryResult(
                success: false,
                attempts: 0,
                statusCode: nil,
                error: "Invalid webhook URL: \(config.url)"
            )
        }
        
        // Encode payload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let payloadData = try? encoder.encode(payload) else {
            return WebhookDeliveryResult(
                success: false,
                attempts: 0,
                statusCode: nil,
                error: "Failed to encode webhook payload"
            )
        }
        
        // Attempt delivery with retries
        var lastError: String?
        var lastStatusCode: Int?
        
        for attempt in 1...(maxRetries + 1) {
            // Wait before retry (not on first attempt)
            if attempt > 1 {
                let delay = initialDelay * pow(backoffFactor, Double(attempt - 2))
                try? await Task.sleep(for: .seconds(delay))
            }
            
            // Build request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payloadData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("FramePeek/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = timeout
            
            // Add custom headers
            if let headers = config.headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            // Send request
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    lastStatusCode = httpResponse.statusCode
                    
                    // Success if 2xx status code
                    if (200..<300).contains(httpResponse.statusCode) {
                        return WebhookDeliveryResult(
                            success: true,
                            attempts: attempt,
                            statusCode: httpResponse.statusCode,
                            error: nil
                        )
                    } else {
                        lastError = "HTTP \(httpResponse.statusCode)"
                    }
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
        
        // All retries exhausted
        return WebhookDeliveryResult(
            success: false,
            attempts: maxRetries + 1,
            statusCode: lastStatusCode,
            error: lastError
        )
    }
    
    /// Prepare a truncated payload from an analysis result
    public func preparePayload(
        from job: AnalysisJob,
        result: AnalysisResult?
    ) -> (payload: WebhookPayload, truncatedFields: [String]) {
        var truncatedFields: [String] = []
        var truncatedResult: TruncatedAnalysisResult? = nil
        
        if let result = result {
            // Truncate bitrate samples if needed
            var truncatedBitrate: TruncatedBitrateResult? = nil
            if let bitrate = result.bitrate {
                let samples = bitrate.samples
                let sampleCount = samples.count
                
                var truncatedSamples: [BitrateSampleOutput]? = samples
                if sampleCount > maxBitrateSamples {
                    truncatedSamples = nil
                    truncatedFields.append("bitrate.samples")
                }
                
                // Calculate statistics
                let bitrateValues = samples.map { $0.bitrate }
                let stats = BitrateStatistics(
                    average: bitrateValues.isEmpty ? 0 : bitrateValues.reduce(0, +) / Double(bitrateValues.count),
                    max: bitrateValues.max() ?? 0,
                    min: bitrateValues.min() ?? 0
                )
                
                truncatedBitrate = TruncatedBitrateResult(
                    mode: bitrate.mode,
                    samples: truncatedSamples,
                    sampleCount: sampleCount,
                    statistics: stats
                )
            }
            
            // Truncate waveforms if needed
            var truncatedWaveforms: [String: [WaveformSampleOutput]]? = result.waveforms
            if let waveforms = result.waveforms {
                for (trackId, samples) in waveforms {
                    if samples.count > maxWaveformSamples {
                        truncatedWaveforms = nil
                        truncatedFields.append("waveforms.\(trackId)")
                        break
                    }
                }
            }
            
            // Truncate keyframes if needed
            var truncatedKeyframes: [KeyframeOutput]? = result.keyframes
            if let keyframes = result.keyframes, keyframes.count > maxKeyframes {
                truncatedKeyframes = nil
                truncatedFields.append("keyframes")
            }
            
            truncatedResult = TruncatedAnalysisResult(
                metadata: result.metadata,
                bitrate: truncatedBitrate,
                gop: result.gop,
                waveforms: truncatedWaveforms,
                sync: result.sync,
                keyframes: truncatedKeyframes
            )
            
            // Check total size and truncate further if needed
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(truncatedResult), data.count > maxPayloadSize {
                // Payload still too large, remove result entirely
                truncatedResult = nil
                truncatedFields = ["result"]
            }
        }
        
        let event = job.status == .complete ? "job.completed" : "job.failed"
        
        let payload = WebhookPayload(
            event: event,
            jobId: job.id,
            status: job.status,
            duration: job.duration ?? 0,
            result: truncatedResult,
            truncated: truncatedFields.isEmpty ? nil : truncatedFields,
            resultUrl: "/jobs/\(job.id)",
            error: job.error
        )
        
        return (payload, truncatedFields)
    }
}
