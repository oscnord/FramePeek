//
//  JobQueue.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation
import FramePeekCore

/// Actor managing the analysis job queue
@MainActor
public final class JobQueue: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var activeJobs: [AnalysisJob] = []
    @Published public private(set) var completedJobs: [CompletedJob] = []
    @Published public private(set) var isProcessing: Bool = false
    
    // MARK: - Configuration
    
    /// Maximum number of concurrent jobs
    public var maxConcurrentJobs: Int = 2
    
    /// Maximum number of completed jobs to keep in history
    public var maxHistoryCount: Int = 100
    
    // MARK: - Private Properties
    
    private var processingTasks: [String: Task<Void, Never>] = [:]
    private let historyStore: JobHistoryStore
    
    // MARK: - Initialization
    
    public init() {
        self.historyStore = JobHistoryStore()
        
        // Load history from disk
        Task {
            await loadHistory()
        }
    }
    
    // MARK: - Public Methods
    
    /// Add a new job to the queue
    public func enqueue(_ job: AnalysisJob) -> AnalysisJob {
        var newJob = job
        newJob.status = .pending
        activeJobs.append(newJob)
        
        // Start processing if we have capacity
        processNextJobIfNeeded()
        
        return newJob
    }
    
    /// Get a job by ID (active or completed)
    public func job(withId id: String) -> AnalysisJob? {
        return activeJobs.first { $0.id == id }
    }
    
    /// Get a completed job by ID
    public func completedJob(withId id: String) -> CompletedJob? {
        return completedJobs.first { $0.id == id }
    }
    
    /// Cancel a job
    public func cancel(jobId: String) -> Bool {
        // Cancel processing task if running
        if let task = processingTasks[jobId] {
            task.cancel()
            processingTasks.removeValue(forKey: jobId)
        }
        
        // Update job status
        if let index = activeJobs.firstIndex(where: { $0.id == jobId }) {
            activeJobs[index].status = .cancelled
            activeJobs[index].completedAt = Date()
            
            // Move to completed
            let job = activeJobs.remove(at: index)
            let completed = CompletedJob(from: job)
            addToHistory(completed)
            
            return true
        }
        
        return false
    }
    
    /// Clear job history
    public func clearHistory() {
        completedJobs.removeAll()
        Task {
            await historyStore.clear()
        }
    }
    
    /// Get count of currently processing jobs
    public var processingCount: Int {
        activeJobs.filter { $0.status == .processing }.count
    }
    
    /// Get count of pending jobs
    public var pendingCount: Int {
        activeJobs.filter { $0.status == .pending }.count
    }
    
    // MARK: - Private Methods
    
    private func processNextJobIfNeeded() {
        // Check if we have capacity
        guard processingCount < maxConcurrentJobs else { return }
        
        // Find next pending job
        guard let index = activeJobs.firstIndex(where: { $0.status == .pending }) else {
            isProcessing = !activeJobs.isEmpty
            return
        }
        
        isProcessing = true
        
        // Start processing
        let job = activeJobs[index]
        activeJobs[index].status = .processing
        activeJobs[index].startedAt = Date()
        
        let task = Task {
            await processJob(job)
        }
        
        processingTasks[job.id] = task
    }
    
    private func processJob(_ job: AnalysisJob) async {
        let engine = AnalysisEngine()
        
        do {
            // Run analysis
            let result = try await engine.analyze(url: job.fileURL, options: job.options)
            
            // Update job with result
            let completedJob: AnalysisJob? = await MainActor.run {
                if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
                    activeJobs[index].status = .complete
                    activeJobs[index].progress = 1.0
                    activeJobs[index].completedAt = Date()
                    activeJobs[index].result = result
                    
                    // Move to completed
                    let completedJob = activeJobs.remove(at: index)
                    let completed = CompletedJob(from: completedJob)
                    addToHistory(completed)
                    
                    processingTasks.removeValue(forKey: job.id)
                    processNextJobIfNeeded()
                    
                    return completedJob
                }
                
                processingTasks.removeValue(forKey: job.id)
                processNextJobIfNeeded()
                return nil
            }
            
            // Trigger webhook if configured
            if let completedJob = completedJob, let webhookConfig = completedJob.webhook {
                await sendWebhook(for: completedJob, config: webhookConfig)
            }
            
        } catch {
            // Handle error
            let failedJob: AnalysisJob? = await MainActor.run {
                if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
                    activeJobs[index].status = .failed
                    activeJobs[index].completedAt = Date()
                    activeJobs[index].error = error.localizedDescription
                    
                    // Move to completed
                    let failedJob = activeJobs.remove(at: index)
                    let completed = CompletedJob(from: failedJob)
                    addToHistory(completed)
                    
                    processingTasks.removeValue(forKey: job.id)
                    processNextJobIfNeeded()
                    
                    return failedJob
                }
                
                processingTasks.removeValue(forKey: job.id)
                processNextJobIfNeeded()
                return nil
            }
            
            // Trigger webhook if configured
            if let failedJob = failedJob, let webhookConfig = failedJob.webhook {
                await sendWebhook(for: failedJob, config: webhookConfig)
            }
        }
    }
    
    /// Send webhook notification for completed/failed job
    private func sendWebhook(for job: AnalysisJob, config: WebhookConfig) async {
        // Prepare payload with truncation
        let (payload, _) = await WebhookService.shared.preparePayload(from: job, result: job.result)
        
        // Send webhook
        let deliveryResult = await WebhookService.shared.send(config: config, payload: payload)
        
        // Log the webhook attempt
        await MainActor.run {
            ServerManager.shared.requestLogger.logWebhook(
                url: config.url,
                success: deliveryResult.success,
                attempts: deliveryResult.attempts,
                statusCode: deliveryResult.statusCode,
                error: deliveryResult.error
            )
        }
    }
    
    private func addToHistory(_ job: CompletedJob) {
        completedJobs.insert(job, at: 0)
        
        // Trim history if needed
        if completedJobs.count > maxHistoryCount {
            completedJobs = Array(completedJobs.prefix(maxHistoryCount))
        }
        
        // Persist to disk
        Task {
            await historyStore.save(completedJobs)
        }
    }
    
    private func loadHistory() async {
        let history = await historyStore.load()
        await MainActor.run {
            self.completedJobs = history
        }
    }
    
    /// Update job progress (called from analysis engine)
    public func updateProgress(jobId: String, phase: AnalysisPhase, progress: Double) {
        if let index = activeJobs.firstIndex(where: { $0.id == jobId }) {
            activeJobs[index].currentPhase = phase
            activeJobs[index].progress = progress
            activeJobs[index].phaseStatuses[phase] = .processing
        }
    }
    
    /// Mark a phase as complete
    public func markPhaseComplete(jobId: String, phase: AnalysisPhase) {
        if let index = activeJobs.firstIndex(where: { $0.id == jobId }) {
            activeJobs[index].phaseStatuses[phase] = .complete
        }
    }
}

// MARK: - Job History Store

/// Persists job history to disk
actor JobHistoryStore {
    
    private let fileURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FramePeek", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        self.fileURL = appDir.appendingPathComponent("job_history.json")
    }
    
    func save(_ jobs: [CompletedJob]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(jobs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save job history: \(error)")
        }
    }
    
    func load() -> [CompletedJob] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([CompletedJob].self, from: data)
        } catch {
            return []
        }
    }
    
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
