//
//  ServerManager.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import Observation
import Hummingbird
import FramePeekCore

/// Configuration for the embedded server
public struct ServerConfiguration: Codable, Sendable {
    public var port: Int
    public var bindAddress: String
    public var enableAuth: Bool
    public var apiKey: String
    public var allowRemoteConnections: Bool
    
    public static let `default` = ServerConfiguration(
        port: 8080,
        bindAddress: "127.0.0.1",
        enableAuth: false,
        apiKey: UUID().uuidString,
        allowRemoteConnections: false
    )
    
    public init(
        port: Int = 8080,
        bindAddress: String = "127.0.0.1",
        enableAuth: Bool = false,
        apiKey: String = UUID().uuidString,
        allowRemoteConnections: Bool = false
    ) {
        self.port = port
        self.bindAddress = bindAddress
        self.enableAuth = enableAuth
        self.apiKey = apiKey
        self.allowRemoteConnections = allowRemoteConnections
    }
    
    /// Effective bind address based on settings
    public var effectiveBindAddress: String {
        allowRemoteConnections ? "0.0.0.0" : "127.0.0.1"
    }
    
    /// Whether auth is required (always required for remote)
    public var requiresAuth: Bool {
        enableAuth || allowRemoteConnections
    }
}

/// Manages the embedded HTTP server lifecycle
@MainActor
@Observable
public final class ServerManager {

    // MARK: - Properties

    public private(set) var isRunning: Bool = false
    public private(set) var startedAt: Date?
    public private(set) var lastError: String?
    public var configuration: ServerConfiguration
    
    // MARK: - Public Properties
    
    public let jobQueue: JobQueue
    public let requestLogger: RequestLogger
    
    /// Server uptime in seconds
    public var uptime: TimeInterval {
        guard let started = startedAt else { return 0 }
        return Date().timeIntervalSince(started)
    }
    
    /// Formatted uptime string
    public var uptimeFormatted: String {
        let seconds = Int(uptime)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
    
    /// Server URL
    public var serverURL: String {
        "http://\(configuration.effectiveBindAddress):\(configuration.port)"
    }
    
    // MARK: - Private Properties
    
    @ObservationIgnored private var serverTask: Task<Void, Error>?
    
    // MARK: - Singleton
    
    public static let shared = ServerManager()
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = Self.loadConfiguration()
        self.jobQueue = JobQueue()
        self.requestLogger = RequestLogger(maxEntries: 20)
    }
    
    // MARK: - Public Methods
    
    /// Start the server
    public func start() async throws {
        guard !isRunning else { return }
        
        lastError = nil
        
        // Capture values needed for the server
        let port = configuration.port
        let bindAddress = configuration.effectiveBindAddress
        let jobQueue = self.jobQueue
        let requestLogger = self.requestLogger
        
        do {
            // Start in background task
            serverTask = Task.detached {
                // Build router with routes
                let router = Router()
                
                // Health endpoint
                router.get("/health") { _, _ -> HealthResponse in
                    let start = Date()
                    let response = HealthResponse(
                        status: "healthy",
                        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                        uptime: await MainActor.run { ServerManager.shared.uptime }
                    )
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/health", statusCode: 200, duration: Date().timeIntervalSince(start)) }
                    return response
                }
                
                // Info endpoint
                router.get("/info") { _, _ -> ServerInfoResponse in
                    let start = Date()
                    let (activeCount, pendingCount) = await MainActor.run {
                        (jobQueue.activeJobs.count, jobQueue.pendingCount)
                    }
                    let response = ServerInfoResponse(
                        name: "FramePeek",
                        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                        capabilities: ["metadata", "bitrate", "gop", "waveform", "sync", "color", "keyframes", "thumbnails"],
                        activeJobs: activeCount,
                        queuedJobs: pendingCount
                    )
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/info", statusCode: 200, duration: Date().timeIntervalSince(start)) }
                    return response
                }
                
                // Analyze by path endpoint
                router.post("/analyze/path") { request, context -> JobCreatedResponse in
                    let start = Date()
                    do {
                        let body = try await request.decode(as: AnalyzePathRequest.self, context: context)
                        
                        let url = URL(fileURLWithPath: body.path)
                        
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 404, duration: Date().timeIntervalSince(start)) }
                            throw HTTPError(.notFound, message: "File not found: \(body.path)")
                        }
                        
                        let options = body.options?.toAnalysisOptions() ?? .metadataOnly
                        let job = AnalysisJob(fileURL: url, options: options, source: .api, webhook: body.webhook)
                        
                        let enqueuedJob = await MainActor.run {
                            jobQueue.enqueue(job)
                        }
                        
                        Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 202, duration: Date().timeIntervalSince(start)) }
                        return JobCreatedResponse(job: enqueuedJob)
                    } catch let error as HTTPError {
                        throw error
                    } catch {
                        Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 400, duration: Date().timeIntervalSince(start)) }
                        throw HTTPError(.badRequest, message: error.localizedDescription)
                    }
                }
                
                // List jobs endpoint
                router.get("/jobs") { _, _ -> JobListResponse in
                    let start = Date()
                    let (activeJobs, completedJobs) = await MainActor.run {
                        (jobQueue.activeJobs, Array(jobQueue.completedJobs.prefix(20)))
                    }
                    
                    let active = activeJobs.map { job in
                        JobListResponse.JobSummary(
                            id: job.id,
                            fileName: job.fileName,
                            status: job.status,
                            progress: job.progress,
                            createdAt: job.createdAt,
                            completedAt: job.completedAt
                        )
                    }
                    
                    let recent = completedJobs.map { job in
                        JobListResponse.JobSummary(
                            id: job.id,
                            fileName: job.fileName,
                            status: job.status,
                            progress: 1.0,
                            createdAt: job.createdAt,
                            completedAt: job.completedAt
                        )
                    }
                    
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/jobs", statusCode: 200, duration: Date().timeIntervalSince(start)) }
                    return JobListResponse(activeJobs: active, recentJobs: recent)
                }
                
                // Get job by ID endpoint
                router.get("/jobs/{id}") { _, context -> JobStatusResponse in
                    let start = Date()
                    let jobId = try context.parameters.require("id", as: String.self)
                    let path = "/jobs/\(jobId)"
                    
                    let (activeJob, completedJob) = await MainActor.run {
                        (jobQueue.job(withId: jobId), jobQueue.completedJob(withId: jobId))
                    }
                    
                    if let job = activeJob {
                        Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 200, duration: Date().timeIntervalSince(start)) }
                        return JobStatusResponse(from: job)
                    }
                    
                    if let completed = completedJob {
                        var job = AnalysisJob(
                            id: completed.id,
                            fileURL: URL(fileURLWithPath: completed.filePath),
                            options: .metadataOnly,
                            source: completed.source
                        )
                        job.status = completed.status
                        job.completedAt = completed.completedAt
                        job.error = completed.error
                        job.result = completed.decodeResult()
                        
                        Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 200, duration: Date().timeIntervalSince(start)) }
                        return JobStatusResponse(from: job)
                    }
                    
                    Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 404, duration: Date().timeIntervalSince(start)) }
                    throw HTTPError(.notFound, message: "Job not found: \(jobId)")
                }
                
                // Cancel job endpoint
                router.delete("/jobs/{id}") { _, context -> CancelResponse in
                    let start = Date()
                    let jobId = try context.parameters.require("id", as: String.self)
                    let path = "/jobs/\(jobId)"
                    
                    let cancelled = await MainActor.run {
                        jobQueue.cancel(jobId: jobId)
                    }
                    
                    if cancelled {
                        Task { @MainActor in requestLogger.log(method: "DELETE", path: path, statusCode: 200, duration: Date().timeIntervalSince(start)) }
                        return CancelResponse(id: jobId, cancelled: true)
                    } else {
                        Task { @MainActor in requestLogger.log(method: "DELETE", path: path, statusCode: 404, duration: Date().timeIntervalSince(start)) }
                        throw HTTPError(.notFound, message: "Job not found or already completed: \(jobId)")
                    }
                }
                
                // Create and run application
                let app = Application(
                    router: router,
                    configuration: .init(
                        address: .hostname(bindAddress, port: port)
                    )
                )
                
                try await app.runService()
            }
            
            // Give server a moment to start
            try await Task.sleep(for: .milliseconds(100))
            
            isRunning = true
            startedAt = Date()
            
            // Save configuration
            saveConfiguration()
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Stop the server
    public func stop() async {
        guard isRunning else { return }
        
        serverTask?.cancel()
        serverTask = nil
        
        isRunning = false
        startedAt = nil
    }
    
    /// Toggle server state
    public func toggle() async {
        if isRunning {
            await stop()
        } else {
            try? await start()
        }
    }
    
    /// Update configuration (requires restart to take effect)
    public func updateConfiguration(_ config: ServerConfiguration) {
        configuration = config
        saveConfiguration()
    }
    
    /// Generate a new API key
    public func regenerateAPIKey() {
        configuration.apiKey = UUID().uuidString
        saveConfiguration()
    }
    
    // MARK: - Configuration Persistence
    
    private static func loadConfiguration() -> ServerConfiguration {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configURL = appSupport.appendingPathComponent("FramePeek/server_config.json")
        
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(ServerConfiguration.self, from: data)
        } catch {
            return .default
        }
    }
    
    private func saveConfiguration() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FramePeek", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        let configURL = appDir.appendingPathComponent("server_config.json")
        
        do {
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("Failed to save server configuration: \(error)")
        }
    }
}

// MARK: - Response Types

struct HealthResponse: ResponseCodable {
    let status: String
    let version: String
    let uptime: TimeInterval
}

struct ServerInfoResponse: ResponseCodable {
    let name: String
    let version: String
    let capabilities: [String]
    let activeJobs: Int
    let queuedJobs: Int
}

struct CancelResponse: ResponseCodable {
    let id: String
    let cancelled: Bool
}

// MARK: - Make API types ResponseCodable

extension JobCreatedResponse: ResponseCodable {}
extension JobListResponse: ResponseCodable {}
extension JobStatusResponse: ResponseCodable {}
