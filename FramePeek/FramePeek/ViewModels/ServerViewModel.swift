//
//  ServerViewModel.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import SwiftUI
import FramePeekCore

/// ViewModel for the Server tab UI
@MainActor
@Observable
public final class ServerViewModel {

    // MARK: - Properties

    /// Reference to the server manager
    public let serverManager: ServerManager

    /// Whether the settings sheet is shown
    public var showSettings: Bool = false

    /// Whether the JSON result sheet is shown
    public var showResultSheet: Bool = false

    /// Selected job for viewing results
    public var selectedJobId: String?

    /// Error alert message
    public var errorMessage: String?
    public var showError: Bool = false

    // MARK: - Computed Properties (pass-through via @Observable)

    public var isRunning: Bool {
        serverManager.isRunning
    }

    public var serverURL: String {
        serverManager.serverURL
    }

    public var uptime: String {
        serverManager.uptimeFormatted
    }

    public var configuration: ServerConfiguration {
        serverManager.configuration
    }

    public var activeJobs: [AnalysisJob] {
        serverManager.jobQueue.activeJobs
    }

    public var completedJobs: [CompletedJob] {
        serverManager.jobQueue.completedJobs
    }

    public var activeJobCount: Int {
        serverManager.jobQueue.activeJobs.count
    }

    public var apiKey: String {
        serverManager.configuration.apiKey
    }

    public var requestLog: [RequestLogEntry] {
        serverManager.requestLogger.entries
    }

    // MARK: - Initialization

    public init() {
        self.serverManager = ServerManager.shared
    }
    
    // MARK: - Request Log
    
    public func clearRequestLog() {
        serverManager.requestLogger.clear()
    }
    
    // MARK: - Server Control
    
    public func startServer() async {
        do {
            try await serverManager.start()
        } catch {
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            showError = true
        }
    }
    
    public func stopServer() async {
        await serverManager.stop()
    }
    
    public func toggleServer() async {
        await serverManager.toggle()
    }
    
    // MARK: - Configuration
    
    public func updatePort(_ port: Int) {
        var config = serverManager.configuration
        config.port = port
        serverManager.updateConfiguration(config)
    }
    
    public func updateAllowRemote(_ allow: Bool) {
        var config = serverManager.configuration
        config.allowRemoteConnections = allow
        // Enable auth if allowing remote
        if allow {
            config.enableAuth = true
        }
        serverManager.updateConfiguration(config)
    }
    
    public func updateEnableAuth(_ enable: Bool) {
        var config = serverManager.configuration
        config.enableAuth = enable
        serverManager.updateConfiguration(config)
    }
    
    public func regenerateAPIKey() {
        serverManager.regenerateAPIKey()
    }
    
    // MARK: - Job Management
    
    public func cancelJob(_ jobId: String) {
        _ = serverManager.jobQueue.cancel(jobId: jobId)
    }
    
    public func clearHistory() {
        serverManager.jobQueue.clearHistory()
    }
    
    public func viewResult(jobId: String) {
        selectedJobId = jobId
        showResultSheet = true
    }
    
    public func getResultJSON(for jobId: String) -> String? {
        if let job = serverManager.jobQueue.job(withId: jobId),
           let result = job.result {
            return formatJSON(result)
        }
        
        if let completed = serverManager.jobQueue.completedJob(withId: jobId),
           let result = completed.decodeResult() {
            return formatJSON(result)
        }
        
        return nil
    }
    
    private func formatJSON(_ result: AnalysisResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        
        return json
    }
    
    // MARK: - Clipboard
    
    public func copyAPIKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(apiKey, forType: .string)
    }
    
    public func copyServerURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serverURL, forType: .string)
    }
}
