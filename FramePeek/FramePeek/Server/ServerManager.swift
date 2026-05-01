//
//  ServerManager.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import HTTPTypes
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
        return Date.now.timeIntervalSince(started)
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
    @ObservationIgnored private var serverMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var serverGeneration: UInt64 = 0
    
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
        let requiresAuth = configuration.requiresAuth
        let apiKey = configuration.apiKey
        let jobQueue = self.jobQueue
        let requestLogger = self.requestLogger
        let probeHost = serverReadinessProbeHost(bindAddress: bindAddress)
        
        serverGeneration &+= 1
        let generation = serverGeneration
        
        do {
            // Start in background task
            let task = Task.detached {
                // Build router with routes
                let router = Router()
                
                func requireAuthorization(
                    _ request: Request,
                    method: String,
                    path: String,
                    start: Date
                ) throws {
                    guard isServerRequestAuthorized(
                        headers: request.headers,
                        requiresAuth: requiresAuth,
                        apiKey: apiKey
                    ) else {
                        Task { @MainActor in
                            requestLogger.log(
                                method: method,
                                path: path,
                                statusCode: 401,
                                duration: Date.now.timeIntervalSince(start)
                            )
                        }
                        throw HTTPError(.unauthorized, message: "Unauthorized")
                    }
                }
                
                // Health endpoint
                router.get("/health") { _, _ -> HealthResponse in
                    let start = Date.now
                    let response = HealthResponse(
                        status: "healthy",
                        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                        uptime: await MainActor.run { ServerManager.shared.uptime }
                    )
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/health", statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
                    return response
                }
                
                // Info endpoint
                router.get("/info") { request, _ -> ServerInfoResponse in
                    let start = Date.now
                    try requireAuthorization(request, method: "GET", path: "/info", start: start)
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
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/info", statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
                    return response
                }
                
                // Analyze by path endpoint
                router.post("/analyze/path") { request, context -> JobCreatedResponse in
                    let start = Date.now
                    do {
                        try requireAuthorization(request, method: "POST", path: "/analyze/path", start: start)
                        let body = try await request.decode(as: AnalyzePathRequest.self, context: context)
                        
                        let url = URL(fileURLWithPath: body.path)
                        
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 404, duration: Date.now.timeIntervalSince(start)) }
                            throw HTTPError(.notFound, message: "File not found: \(body.path)")
                        }
                        
                        let options = body.options?.toAnalysisOptions() ?? .metadataOnly
                        let job = AnalysisJob(fileURL: url, options: options, source: .api, webhook: body.webhook)
                        
                        let enqueuedJob = await MainActor.run {
                            jobQueue.enqueue(job)
                        }
                        
                        Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 202, duration: Date.now.timeIntervalSince(start)) }
                        return JobCreatedResponse(job: enqueuedJob)
                    } catch let error as HTTPError {
                        throw error
                    } catch {
                        Task { @MainActor in requestLogger.log(method: "POST", path: "/analyze/path", statusCode: 400, duration: Date.now.timeIntervalSince(start)) }
                        throw HTTPError(.badRequest, message: error.localizedDescription)
                    }
                }
                
                // List jobs endpoint
                router.get("/jobs") { request, _ -> JobListResponse in
                    let start = Date.now
                    try requireAuthorization(request, method: "GET", path: "/jobs", start: start)
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
                    
                    Task { @MainActor in requestLogger.log(method: "GET", path: "/jobs", statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
                    return JobListResponse(activeJobs: active, recentJobs: recent)
                }
                
                // Get job by ID endpoint
                router.get("/jobs/{id}") { request, context -> JobStatusResponse in
                    let start = Date.now
                    let jobId = try context.parameters.require("id", as: String.self)
                    let path = "/jobs/\(jobId)"
                    try requireAuthorization(request, method: "GET", path: path, start: start)
                    
                    let (activeJob, completedJob) = await MainActor.run {
                        (jobQueue.job(withId: jobId), jobQueue.completedJob(withId: jobId))
                    }
                    
                    if let job = activeJob {
                        Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
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
                        
                        Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
                        return JobStatusResponse(from: job)
                    }
                    
                    Task { @MainActor in requestLogger.log(method: "GET", path: path, statusCode: 404, duration: Date.now.timeIntervalSince(start)) }
                    throw HTTPError(.notFound, message: "Job not found: \(jobId)")
                }
                
                // Cancel job endpoint
                router.delete("/jobs/{id}") { request, context -> CancelResponse in
                    let start = Date.now
                    let jobId = try context.parameters.require("id", as: String.self)
                    let path = "/jobs/\(jobId)"
                    try requireAuthorization(request, method: "DELETE", path: path, start: start)
                    
                    let cancelled = await MainActor.run {
                        jobQueue.cancel(jobId: jobId)
                    }
                    
                    if cancelled {
                        Task { @MainActor in requestLogger.log(method: "DELETE", path: path, statusCode: 200, duration: Date.now.timeIntervalSince(start)) }
                        return CancelResponse(id: jobId, cancelled: true)
                    } else {
                        Task { @MainActor in requestLogger.log(method: "DELETE", path: path, statusCode: 404, duration: Date.now.timeIntervalSince(start)) }
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
            serverTask = task
            
            // Verify server is reachable before declaring it running.
            try await waitForServerReadiness(host: probeHost, port: port)
            
            isRunning = true
            startedAt = Date.now
            beginMonitoringServerTask(task, generation: generation)
            
            // Save configuration
            saveConfiguration()
            
        } catch {
            serverTask?.cancel()
            serverTask = nil
            serverMonitorTask?.cancel()
            serverMonitorTask = nil
            isRunning = false
            startedAt = nil
            lastError = error.localizedDescription
            throw error
        }
    }
    
    /// Stop the server
    public func stop() async {
        guard isRunning || serverTask != nil else { return }
        
        serverGeneration &+= 1
        serverMonitorTask?.cancel()
        serverMonitorTask = nil
        
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
    
    // MARK: - Lifecycle Monitoring
    
    private func beginMonitoringServerTask(_ task: Task<Void, Error>, generation: UInt64) {
        serverMonitorTask?.cancel()
        serverMonitorTask = Task { [weak self] in
            do {
                try await task.value
                await MainActor.run {
                    guard let self, self.serverGeneration == generation else { return }
                    self.isRunning = false
                    self.startedAt = nil
                    self.serverTask = nil
                }
            } catch is CancellationError {
                // Expected during normal shutdown.
            } catch {
                await MainActor.run {
                    guard let self, self.serverGeneration == generation else { return }
                    self.lastError = error.localizedDescription
                    self.isRunning = false
                    self.startedAt = nil
                    self.serverTask = nil
                }
            }
        }
    }
    
    private func waitForServerReadiness(
        host: String,
        port: Int,
        timeout: Duration = .seconds(3)
    ) async throws {
        guard let url = URL(string: "http://\(host):\(port)/health") else {
            throw HTTPError(.internalServerError, message: "Invalid server probe URL")
        }
        
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        
        while clock.now < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.25
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let statusCode = (response as? HTTPURLResponse)?.statusCode,
                   (200..<500).contains(statusCode) {
                    return
                }
            } catch {
                // Retry until timeout.
            }
            
            try await Task.sleep(for: .milliseconds(100))
        }
        
        throw HTTPError(.serviceUnavailable, message: "Server failed to start on \(host):\(port)")
    }
    
    // MARK: - Configuration Persistence
    
    private static var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    private static func loadConfiguration() -> ServerConfiguration {
        let configURL = appSupportDirectory.appendingPathComponent("FramePeek/server_config.json")

        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(ServerConfiguration.self, from: data)
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Log.server.error("Failed to load server configuration: \(error.localizedDescription)")
            }
            return .default
        }
    }

    private func saveConfiguration() {
        let appDir = Self.appSupportDirectory.appendingPathComponent("FramePeek", isDirectory: true)

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let configURL = appDir.appendingPathComponent("server_config.json")
        
        do {
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: configURL, options: .atomic)
        } catch {
            Log.server.error("Failed to save server configuration: \(error.localizedDescription)")
        }
    }
}

func serverReadinessProbeHost(bindAddress: String) -> String {
    bindAddress == "0.0.0.0" ? "127.0.0.1" : bindAddress
}

func isServerRequestAuthorized(
    headers: HTTPFields,
    requiresAuth: Bool,
    apiKey: String
) -> Bool {
    guard requiresAuth else { return true }
    let expectedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !expectedKey.isEmpty else { return false }

    if let authorization = headers[.authorization]?.trimmingCharacters(in: .whitespacesAndNewlines) {
        let lowercased = authorization.lowercased()
        if lowercased.hasPrefix("bearer ") {
            let bearerToken = String(authorization.dropFirst("Bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if bearerToken == expectedKey {
                return true
            }
        } else if authorization == expectedKey {
            return true
        }
    }

    if let xAPIKeyHeader = HTTPField.Name("x-api-key"),
       let xAPIKey = headers[xAPIKeyHeader]?.trimmingCharacters(in: .whitespacesAndNewlines),
       xAPIKey == expectedKey {
        return true
    }

    return false
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
