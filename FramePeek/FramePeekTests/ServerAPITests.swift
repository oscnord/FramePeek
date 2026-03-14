//
//  ServerAPITests.swift
//  FramePeekTests
//
//  Unit tests for FramePeek Server API components
//

import Testing
import Foundation
@testable import FramePeek
@testable import FramePeekCore

// MARK: - RequestLogEntry Tests

struct RequestLogEntryTests {
    
    @Test func requestLogEntry_initializesCorrectly() {
        let entry = RequestLogEntry(
            method: "GET",
            path: "/health",
            statusCode: 200,
            duration: 0.05
        )
        
        #expect(entry.method == "GET")
        #expect(entry.path == "/health")
        #expect(entry.statusCode == 200)
        #expect(entry.duration == 0.05)
        #expect(entry.isWebhook == false)
        #expect(entry.webhookAttempts == nil)
        #expect(entry.webhookError == nil)
    }
    
    @Test func requestLogEntry_initializesWithWebhook() {
        let entry = RequestLogEntry(
            method: "HOOK",
            path: "https://example.com/webhook",
            statusCode: 200,
            duration: 0,
            isWebhook: true,
            webhookAttempts: 2,
            webhookError: nil
        )
        
        #expect(entry.isWebhook == true)
        #expect(entry.webhookAttempts == 2)
    }
    
    @Test func requestLogEntry_initializesWithWebhookError() {
        let entry = RequestLogEntry(
            method: "HOOK",
            path: "https://example.com/webhook",
            statusCode: 0,
            duration: 0,
            isWebhook: true,
            webhookAttempts: 3,
            webhookError: "Connection refused"
        )
        
        #expect(entry.isWebhook == true)
        #expect(entry.webhookAttempts == 3)
        #expect(entry.webhookError == "Connection refused")
    }
    
    @Test func requestLogEntry_timeString_formatsCorrectly() {
        let entry = RequestLogEntry(
            method: "GET",
            path: "/test",
            statusCode: 200,
            duration: 0.1
        )
        
        // timeString should be in HH:mm:ss format
        #expect(entry.timeString.contains(":"))
        #expect(entry.timeString.count == 8) // "HH:mm:ss"
    }
    
    @Test func requestLogEntry_durationString_formatsMilliseconds() {
        let entry = RequestLogEntry(
            method: "GET",
            path: "/test",
            statusCode: 200,
            duration: 0.05
        )
        
        #expect(entry.durationString == "50ms")
    }
    
    @Test func requestLogEntry_durationString_formatsSubMillisecond() {
        let entry = RequestLogEntry(
            method: "GET",
            path: "/test",
            statusCode: 200,
            duration: 0.0005
        )
        
        #expect(entry.durationString == "<1ms")
    }
    
    @Test func requestLogEntry_durationString_formatsSeconds() {
        let entry = RequestLogEntry(
            method: "GET",
            path: "/test",
            statusCode: 200,
            duration: 1.5
        )
        
        #expect(entry.durationString == "1.50s")
    }
    
    @Test func requestLogEntry_statusCategory_success() {
        let entry200 = RequestLogEntry(method: "GET", path: "/", statusCode: 200, duration: 0)
        let entry201 = RequestLogEntry(method: "POST", path: "/", statusCode: 201, duration: 0)
        let entry204 = RequestLogEntry(method: "DELETE", path: "/", statusCode: 204, duration: 0)
        
        #expect(entry200.statusCategory == .success)
        #expect(entry201.statusCategory == .success)
        #expect(entry204.statusCategory == .success)
    }
    
    @Test func requestLogEntry_statusCategory_clientError() {
        let entry400 = RequestLogEntry(method: "POST", path: "/", statusCode: 400, duration: 0)
        let entry404 = RequestLogEntry(method: "GET", path: "/", statusCode: 404, duration: 0)
        let entry401 = RequestLogEntry(method: "GET", path: "/", statusCode: 401, duration: 0)
        
        #expect(entry400.statusCategory == .clientError)
        #expect(entry404.statusCategory == .clientError)
        #expect(entry401.statusCategory == .clientError)
    }
    
    @Test func requestLogEntry_statusCategory_serverError() {
        let entry500 = RequestLogEntry(method: "GET", path: "/", statusCode: 500, duration: 0)
        let entry503 = RequestLogEntry(method: "GET", path: "/", statusCode: 503, duration: 0)
        
        #expect(entry500.statusCategory == .serverError)
        #expect(entry503.statusCategory == .serverError)
    }
    
    @Test func requestLogEntry_statusCategory_other() {
        let entry100 = RequestLogEntry(method: "GET", path: "/", statusCode: 100, duration: 0)
        let entry0 = RequestLogEntry(method: "GET", path: "/", statusCode: 0, duration: 0)
        
        #expect(entry100.statusCategory == .other)
        #expect(entry0.statusCategory == .other)
    }
}

// MARK: - RequestLogger Tests

@MainActor
struct RequestLoggerTests {
    
    @Test func requestLogger_initializesEmpty() {
        let logger = RequestLogger(maxEntries: 10)
        
        #expect(logger.entries.isEmpty)
        #expect(logger.maxEntries == 10)
    }
    
    @Test func requestLogger_logsEntry() {
        let logger = RequestLogger(maxEntries: 10)
        
        logger.log(method: "GET", path: "/health", statusCode: 200, duration: 0.05)
        
        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.method == "GET")
        #expect(logger.entries.first?.path == "/health")
    }
    
    @Test func requestLogger_insertsAtFront() {
        let logger = RequestLogger(maxEntries: 10)
        
        logger.log(method: "GET", path: "/first", statusCode: 200, duration: 0.01)
        logger.log(method: "POST", path: "/second", statusCode: 201, duration: 0.02)
        
        #expect(logger.entries.count == 2)
        #expect(logger.entries.first?.path == "/second")
        #expect(logger.entries.last?.path == "/first")
    }
    
    @Test func requestLogger_trimsToMaxEntries() {
        let logger = RequestLogger(maxEntries: 3)
        
        logger.log(method: "GET", path: "/1", statusCode: 200, duration: 0)
        logger.log(method: "GET", path: "/2", statusCode: 200, duration: 0)
        logger.log(method: "GET", path: "/3", statusCode: 200, duration: 0)
        logger.log(method: "GET", path: "/4", statusCode: 200, duration: 0)
        logger.log(method: "GET", path: "/5", statusCode: 200, duration: 0)
        
        #expect(logger.entries.count == 3)
        // Most recent entries should be kept
        #expect(logger.entries[0].path == "/5")
        #expect(logger.entries[1].path == "/4")
        #expect(logger.entries[2].path == "/3")
    }
    
    @Test func requestLogger_logsWebhook() {
        let logger = RequestLogger(maxEntries: 10)
        
        logger.logWebhook(
            url: "https://example.com/webhook",
            success: true,
            attempts: 1,
            statusCode: 200,
            error: nil
        )
        
        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.isWebhook == true)
        #expect(logger.entries.first?.method == "HOOK")
        #expect(logger.entries.first?.path == "https://example.com/webhook")
        #expect(logger.entries.first?.webhookAttempts == 1)
        #expect(logger.entries.first?.webhookError == nil)
    }
    
    @Test func requestLogger_logsWebhookWithError() {
        let logger = RequestLogger(maxEntries: 10)
        
        logger.logWebhook(
            url: "https://example.com/webhook",
            success: false,
            attempts: 3,
            statusCode: nil,
            error: "Connection timeout"
        )
        
        #expect(logger.entries.first?.isWebhook == true)
        #expect(logger.entries.first?.statusCode == 0)
        #expect(logger.entries.first?.webhookAttempts == 3)
        #expect(logger.entries.first?.webhookError == "Connection timeout")
    }
    
    @Test func requestLogger_clear() {
        let logger = RequestLogger(maxEntries: 10)
        
        logger.log(method: "GET", path: "/1", statusCode: 200, duration: 0)
        logger.log(method: "GET", path: "/2", statusCode: 200, duration: 0)
        
        #expect(logger.entries.count == 2)
        
        logger.clear()
        
        #expect(logger.entries.isEmpty)
    }
}

// MARK: - JobStatus Tests

struct JobStatusTests {
    
    @Test func jobStatus_rawValues() {
        #expect(JobStatus.pending.rawValue == "pending")
        #expect(JobStatus.processing.rawValue == "processing")
        #expect(JobStatus.complete.rawValue == "complete")
        #expect(JobStatus.failed.rawValue == "failed")
        #expect(JobStatus.cancelled.rawValue == "cancelled")
    }
    
    @Test func jobStatus_isCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let original = JobStatus.complete
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(JobStatus.self, from: data)
        
        #expect(decoded == original)
    }
}

// MARK: - JobPhaseStatus Tests

struct JobPhaseStatusTests {
    
    @Test func jobPhaseStatus_rawValues() {
        #expect(JobPhaseStatus.pending.rawValue == "pending")
        #expect(JobPhaseStatus.processing.rawValue == "processing")
        #expect(JobPhaseStatus.complete.rawValue == "complete")
        #expect(JobPhaseStatus.skipped.rawValue == "skipped")
        #expect(JobPhaseStatus.failed.rawValue == "failed")
    }
}

// MARK: - JobSource Tests

struct JobSourceTests {
    
    @Test func jobSource_rawValues() {
        #expect(JobSource.api.rawValue == "api")
        #expect(JobSource.upload.rawValue == "upload")
        #expect(JobSource.gui.rawValue == "gui")
    }
}

// MARK: - WebhookConfig Tests

struct WebhookConfigTests {
    
    @Test func webhookConfig_initializesCorrectly() {
        let config = WebhookConfig(
            url: "https://example.com/webhook",
            headers: ["Authorization": "Bearer token123"]
        )
        
        #expect(config.url == "https://example.com/webhook")
        #expect(config.headers?["Authorization"] == "Bearer token123")
    }
    
    @Test func webhookConfig_initializesWithoutHeaders() {
        let config = WebhookConfig(url: "https://example.com/webhook")
        
        #expect(config.url == "https://example.com/webhook")
        #expect(config.headers == nil)
    }
    
    @Test func webhookConfig_isCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let original = WebhookConfig(
            url: "https://example.com/webhook",
            headers: ["X-Custom": "value"]
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebhookConfig.self, from: data)
        
        #expect(decoded.url == original.url)
        #expect(decoded.headers?["X-Custom"] == "value")
    }
}

// MARK: - WebhookDeliveryResult Tests

struct WebhookDeliveryResultTests {
    
    @Test func webhookDeliveryResult_success() {
        let result = WebhookDeliveryResult(
            success: true,
            attempts: 1,
            statusCode: 200,
            error: nil
        )
        
        #expect(result.success == true)
        #expect(result.attempts == 1)
        #expect(result.statusCode == 200)
        #expect(result.error == nil)
    }
    
    @Test func webhookDeliveryResult_failureWithRetries() {
        let result = WebhookDeliveryResult(
            success: false,
            attempts: 4,
            statusCode: 503,
            error: "Service unavailable"
        )
        
        #expect(result.success == false)
        #expect(result.attempts == 4)
        #expect(result.statusCode == 503)
        #expect(result.error == "Service unavailable")
    }
    
    @Test func webhookDeliveryResult_failureNoStatusCode() {
        let result = WebhookDeliveryResult(
            success: false,
            attempts: 4,
            statusCode: nil,
            error: "Connection refused"
        )
        
        #expect(result.success == false)
        #expect(result.statusCode == nil)
        #expect(result.error == "Connection refused")
    }
}

// MARK: - BitrateStatistics Tests

struct BitrateStatisticsTests {
    
    @Test func bitrateStatistics_initializesCorrectly() {
        let stats = BitrateStatistics(
            average: 5_000_000,
            max: 10_000_000,
            min: 1_000_000
        )
        
        #expect(stats.average == 5_000_000)
        #expect(stats.max == 10_000_000)
        #expect(stats.min == 1_000_000)
    }
    
    @Test func bitrateStatistics_isCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let original = BitrateStatistics(average: 5.0, max: 10.0, min: 1.0)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BitrateStatistics.self, from: data)
        
        #expect(decoded.average == original.average)
        #expect(decoded.max == original.max)
        #expect(decoded.min == original.min)
    }
}

// MARK: - AnalyzePathRequest Tests

struct AnalyzePathRequestTests {
    
    @Test func analyzePathRequest_decodesBasic() throws {
        let json = """
        {
            "path": "/path/to/video.mp4"
        }
        """
        
        let decoder = JSONDecoder()
        let request = try decoder.decode(AnalyzePathRequest.self, from: json.data(using: .utf8)!)
        
        #expect(request.path == "/path/to/video.mp4")
        #expect(request.options == nil)
        #expect(request.webhook == nil)
    }
    
    @Test func analyzePathRequest_decodesWithOptions() throws {
        let json = """
        {
            "path": "/path/to/video.mp4",
            "options": {
                "info": true,
                "bitrate": true,
                "gop": false
            }
        }
        """
        
        let decoder = JSONDecoder()
        let request = try decoder.decode(AnalyzePathRequest.self, from: json.data(using: .utf8)!)
        
        #expect(request.path == "/path/to/video.mp4")
        #expect(request.options?.info == true)
        #expect(request.options?.bitrate == true)
        #expect(request.options?.gop == false)
    }
    
    @Test func analyzePathRequest_decodesWithWebhook() throws {
        let json = """
        {
            "path": "/path/to/video.mp4",
            "options": {
                "info": true
            },
            "webhook": {
                "url": "https://example.com/webhook",
                "headers": {
                    "Authorization": "Bearer token"
                }
            }
        }
        """
        
        let decoder = JSONDecoder()
        let request = try decoder.decode(AnalyzePathRequest.self, from: json.data(using: .utf8)!)
        
        #expect(request.webhook?.url == "https://example.com/webhook")
        #expect(request.webhook?.headers?["Authorization"] == "Bearer token")
    }
    
    @Test func analyzePathRequest_decodesAllOption() throws {
        let json = """
        {
            "path": "/path/to/video.mp4",
            "options": {
                "all": true
            }
        }
        """
        
        let decoder = JSONDecoder()
        let request = try decoder.decode(AnalyzePathRequest.self, from: json.data(using: .utf8)!)
        
        #expect(request.options?.all == true)
    }
    
    @Test func analyzePathRequest_decodesAdvancedOptions() throws {
        let json = """
        {
            "path": "/path/to/video.mp4",
            "options": {
                "bitrate": true,
                "bitrateMode": "gop",
                "maxSamples": 5000,
                "gopFrameTypes": true,
                "gopMaxSeconds": 30.0
            }
        }
        """
        
        let decoder = JSONDecoder()
        let request = try decoder.decode(AnalyzePathRequest.self, from: json.data(using: .utf8)!)
        
        #expect(request.options?.bitrateMode == "gop")
        #expect(request.options?.maxSamples == 5000)
        #expect(request.options?.gopFrameTypes == true)
        #expect(request.options?.gopMaxSeconds == 30.0)
    }
}

// MARK: - AnalyzeOptions ToAnalysisOptions Tests

struct AnalyzeOptionsConversionTests {
    
    @Test func analyzeOptions_toAnalysisOptions_defaultsToMetadata() throws {
        let json = """
        {}
        """
        
        let decoder = JSONDecoder()
        let options = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: json.data(using: .utf8)!)
        let analysisOptions = options.toAnalysisOptions()
        
        #expect(analysisOptions.includeMetadata == true)
        #expect(analysisOptions.includeBitrate == false)
        #expect(analysisOptions.includeGOP == false)
    }
    
    @Test func analyzeOptions_toAnalysisOptions_allEnabled() throws {
        let json = """
        {
            "all": true
        }
        """
        
        let decoder = JSONDecoder()
        let options = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: json.data(using: .utf8)!)
        let analysisOptions = options.toAnalysisOptions()
        
        #expect(analysisOptions.includeMetadata == true)
        #expect(analysisOptions.includeBitrate == true)
        #expect(analysisOptions.includeGOP == true)
        #expect(analysisOptions.includeWaveform == true)
        #expect(analysisOptions.includeSync == true)
        #expect(analysisOptions.includeColor == true)
        #expect(analysisOptions.includeKeyframes == true)
    }
    
    @Test func analyzeOptions_toAnalysisOptions_selectiveOptions() throws {
        let json = """
        {
            "bitrate": true,
            "gop": true
        }
        """
        
        let decoder = JSONDecoder()
        let options = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: json.data(using: .utf8)!)
        let analysisOptions = options.toAnalysisOptions()
        
        #expect(analysisOptions.includeMetadata == false)
        #expect(analysisOptions.includeBitrate == true)
        #expect(analysisOptions.includeGOP == true)
        #expect(analysisOptions.includeWaveform == false)
    }
    
    @Test func analyzeOptions_toAnalysisOptions_bitrateMode() throws {
        let jsonFrame = """
        {
            "bitrate": true,
            "bitrateMode": "frame"
        }
        """
        
        let jsonGop = """
        {
            "bitrate": true,
            "bitrateMode": "gop"
        }
        """
        
        let decoder = JSONDecoder()
        
        let frameOptions = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: jsonFrame.data(using: .utf8)!)
        let gopOptions = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: jsonGop.data(using: .utf8)!)
        
        #expect(frameOptions.toAnalysisOptions().bitrateMode == .frame)
        #expect(gopOptions.toAnalysisOptions().bitrateMode == .gop)
    }
    
    @Test func analyzeOptions_toAnalysisOptions_maxSamples() throws {
        let json = """
        {
            "bitrate": true,
            "maxSamples": 5000
        }
        """
        
        let decoder = JSONDecoder()
        let options = try decoder.decode(AnalyzePathRequest.AnalyzeOptions.self, from: json.data(using: .utf8)!)
        let analysisOptions = options.toAnalysisOptions()
        
        #expect(analysisOptions.maxSamples == 5000)
    }
}

// MARK: - ServerConfiguration Tests

struct ServerConfigurationTests {
    
    @Test func serverConfiguration_defaultValues() {
        let config = ServerConfiguration.default
        
        #expect(config.port == 8080)
        #expect(config.bindAddress == "127.0.0.1")
        #expect(config.enableAuth == false)
        #expect(config.allowRemoteConnections == false)
    }
    
    @Test func serverConfiguration_effectiveBindAddress_local() {
        let config = ServerConfiguration(allowRemoteConnections: false)
        
        #expect(config.effectiveBindAddress == "127.0.0.1")
    }
    
    @Test func serverConfiguration_effectiveBindAddress_remote() {
        let config = ServerConfiguration(allowRemoteConnections: true)
        
        #expect(config.effectiveBindAddress == "0.0.0.0")
    }
    
    @Test func serverConfiguration_requiresAuth_whenAuthEnabled() {
        let config = ServerConfiguration(enableAuth: true, allowRemoteConnections: false)
        
        #expect(config.requiresAuth == true)
    }
    
    @Test func serverConfiguration_requiresAuth_whenRemoteEnabled() {
        let config = ServerConfiguration(enableAuth: false, allowRemoteConnections: true)
        
        #expect(config.requiresAuth == true)
    }
    
    @Test func serverConfiguration_requiresAuth_whenBothDisabled() {
        let config = ServerConfiguration(enableAuth: false, allowRemoteConnections: false)
        
        #expect(config.requiresAuth == false)
    }
    
    @Test func serverConfiguration_isCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let original = ServerConfiguration(
            port: 9090,
            bindAddress: "127.0.0.1",
            enableAuth: true,
            apiKey: "test-api-key",
            allowRemoteConnections: true
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ServerConfiguration.self, from: data)
        
        #expect(decoded.port == 9090)
        #expect(decoded.enableAuth == true)
        #expect(decoded.apiKey == "test-api-key")
        #expect(decoded.allowRemoteConnections == true)
    }
}

// MARK: - WebhookPayload Tests

struct WebhookPayloadTests {
    
    @Test func webhookPayload_initializesCorrectly() {
        let payload = WebhookPayload(
            event: "job.completed",
            jobId: "test-123",
            status: .complete,
            duration: 45.5,
            result: nil,
            truncated: nil,
            resultUrl: "/jobs/test-123",
            error: nil
        )
        
        #expect(payload.event == "job.completed")
        #expect(payload.jobId == "test-123")
        #expect(payload.status == .complete)
        #expect(payload.duration == 45.5)
        #expect(payload.resultUrl == "/jobs/test-123")
        #expect(payload.error == nil)
    }
    
    @Test func webhookPayload_failedJob() {
        let payload = WebhookPayload(
            event: "job.failed",
            jobId: "test-456",
            status: .failed,
            duration: 10.0,
            result: nil,
            truncated: nil,
            resultUrl: "/jobs/test-456",
            error: "File not found"
        )
        
        #expect(payload.event == "job.failed")
        #expect(payload.status == .failed)
        #expect(payload.error == "File not found")
    }
    
    @Test func webhookPayload_withTruncatedFields() {
        let payload = WebhookPayload(
            event: "job.completed",
            jobId: "test-789",
            status: .complete,
            duration: 120.0,
            result: nil,
            truncated: ["bitrate.samples", "keyframes"],
            resultUrl: "/jobs/test-789",
            error: nil
        )
        
        #expect(payload.truncated?.count == 2)
        #expect(payload.truncated?.contains("bitrate.samples") == true)
        #expect(payload.truncated?.contains("keyframes") == true)
    }
    
    @Test func webhookPayload_isCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let original = WebhookPayload(
            event: "job.completed",
            jobId: "test-123",
            status: .complete,
            duration: 45.5,
            result: nil,
            truncated: ["bitrate.samples"],
            resultUrl: "/jobs/test-123",
            error: nil
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WebhookPayload.self, from: data)
        
        #expect(decoded.event == original.event)
        #expect(decoded.jobId == original.jobId)
        #expect(decoded.status == original.status)
        #expect(decoded.truncated == original.truncated)
    }
}

// MARK: - TruncatedBitrateResult Tests

struct TruncatedBitrateResultTests {
    
    @Test func truncatedBitrateResult_withSamples() {
        let result = TruncatedBitrateResult(
            mode: "second",
            samples: [],
            sampleCount: 100,
            statistics: BitrateStatistics(average: 5.0, max: 10.0, min: 1.0)
        )
        
        #expect(result.mode == "second")
        #expect(result.samples != nil)
        #expect(result.sampleCount == 100)
        #expect(result.statistics?.average == 5.0)
    }
    
    @Test func truncatedBitrateResult_truncated() {
        let result = TruncatedBitrateResult(
            mode: "frame",
            samples: nil,  // Truncated
            sampleCount: 50000,
            statistics: BitrateStatistics(average: 5.0, max: 10.0, min: 1.0)
        )
        
        #expect(result.samples == nil)
        #expect(result.sampleCount == 50000)
        #expect(result.statistics != nil)
    }
}

// MARK: - AnalysisJob Tests

struct AnalysisJobTests {
    
    @Test func analysisJob_initializesCorrectly() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let job = AnalysisJob(
            fileURL: url,
            options: .metadataOnly,
            source: .api
        )
        
        #expect(job.fileURL == url)
        #expect(job.fileName == "video.mp4")
        #expect(job.source == .api)
        #expect(job.status == .pending)
        #expect(job.progress == 0)
        #expect(job.webhook == nil)
    }
    
    @Test func analysisJob_initializesWithWebhook() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let webhook = WebhookConfig(url: "https://example.com/webhook")
        let job = AnalysisJob(
            fileURL: url,
            options: .metadataOnly,
            source: .api,
            webhook: webhook
        )
        
        #expect(job.webhook?.url == "https://example.com/webhook")
    }
    
    @Test func analysisJob_initializesWithCustomId() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let job = AnalysisJob(
            id: "custom-id-123",
            fileURL: url,
            options: .metadataOnly,
            source: .gui
        )
        
        #expect(job.id == "custom-id-123")
    }
    
    @Test func analysisJob_duration_nil_whenNotStarted() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        
        #expect(job.duration == nil)
        #expect(job.durationFormatted == nil)
    }
    
    @Test func analysisJob_durationFormatted_milliseconds() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.startedAt = Date.now
        job.completedAt = job.startedAt?.addingTimeInterval(0.5)
        
        #expect(job.durationFormatted == "500ms")
    }
    
    @Test func analysisJob_durationFormatted_seconds() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.startedAt = Date.now
        job.completedAt = job.startedAt?.addingTimeInterval(5.5)
        
        #expect(job.durationFormatted == "5.5s")
    }
    
    @Test func analysisJob_durationFormatted_minutes() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.startedAt = Date.now
        job.completedAt = job.startedAt?.addingTimeInterval(125)  // 2m 5s
        
        #expect(job.durationFormatted == "2m 5s")
    }
}

// MARK: - CompletedJob Tests

struct CompletedJobTests {
    
    @Test func completedJob_createsFromAnalysisJob() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.status = .complete
        job.startedAt = Date.now.addingTimeInterval(-10)
        job.completedAt = Date.now
        
        let completed = CompletedJob(from: job)
        
        #expect(completed.id == job.id)
        #expect(completed.fileName == "video.mp4")
        #expect(completed.filePath == "/path/to/video.mp4")
        #expect(completed.source == .api)
        #expect(completed.status == .complete)
    }
    
    @Test func completedJob_durationFormatted() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.status = .complete
        job.startedAt = Date.now
        job.completedAt = job.startedAt?.addingTimeInterval(5.5)
        
        let completed = CompletedJob(from: job)
        
        #expect(completed.durationFormatted == "5.5s")
    }
    
    @Test func completedJob_withError() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        var job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        job.status = .failed
        job.error = "File could not be opened"
        job.startedAt = Date.now
        job.completedAt = Date.now
        
        let completed = CompletedJob(from: job)
        
        #expect(completed.status == .failed)
        #expect(completed.error == "File could not be opened")
    }
}

// MARK: - JobCreatedResponse Tests

struct JobCreatedResponseTests {
    
    @Test func jobCreatedResponse_createsFromJob() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let job = AnalysisJob(
            id: "test-job-id",
            fileURL: url,
            options: .metadataOnly,
            source: .api
        )
        
        let response = JobCreatedResponse(job: job)
        
        #expect(response.id == "test-job-id")
        #expect(response.status == .pending)
        #expect(response.message == "Job created successfully")
    }
    
    @Test func jobCreatedResponse_isCodable() throws {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let job = AnalysisJob(fileURL: url, options: .metadataOnly, source: .api)
        let response = JobCreatedResponse(job: job)
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(JobCreatedResponse.self, from: data)
        
        #expect(decoded.id == response.id)
        #expect(decoded.status == response.status)
        #expect(decoded.message == response.message)
    }
}
