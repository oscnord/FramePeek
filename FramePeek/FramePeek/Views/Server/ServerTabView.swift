//
//  ServerTabView.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import SwiftUI
import FramePeekCore

/// Main view for the Server tab
struct ServerTabView: View {
    @StateObject private var viewModel = ServerViewModel()
    @State private var selectedTab: ServerSubTab = .server
    
    enum ServerSubTab: String, CaseIterable {
        case server = "Server"
        case apiDocs = "API Docs"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(ServerSubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, DesignSystem.Padding.lg)
            .padding(.bottom, DesignSystem.Padding.md)
            
            // Tab content
            switch selectedTab {
            case .server:
                ServerContentView(viewModel: viewModel)
            case .apiDocs:
                APIDocumentationView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $viewModel.showSettings) {
            ServerSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showResultSheet) {
            if let jobId = viewModel.selectedJobId {
                JobResultSheet(viewModel: viewModel, jobId: jobId)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
}

// MARK: - Server Content View

struct ServerContentView: View {
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl2) {
                // Server Status Section
                ServerStatusSection(viewModel: viewModel)
                
                // Request Log Section
                RequestLogSection(viewModel: viewModel)
                
                // Active Jobs Section
                ActiveJobsSection(viewModel: viewModel)
                
                // Job History Section
                JobHistorySection(viewModel: viewModel)
            }
            .padding(DesignSystem.Padding.lg3)
        }
    }
}

// MARK: - Server Status Section

struct ServerStatusSection: View {
    @ObservedObject var viewModel: ServerViewModel
    
    // Timer to update uptime display
    @State private var uptimeRefreshTrigger = false
    let uptimeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                HStack {
                    // Status indicator
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 12, height: 12)
                    
                    Text(viewModel.isRunning ? "Server Running" : "Server Offline")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Start/Stop button
                    Button(action: {
                        Task {
                            await viewModel.toggleServer()
                        }
                    }) {
                        Text(viewModel.isRunning ? "Stop Server" : "Start Server")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRunning ? .red : .accentColor)
                }
                
                Divider()
                
                // Server info
                HStack(spacing: DesignSystem.Spacing.xl2) {
                    if viewModel.isRunning {
                        // URL
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("URL:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.serverURL)
                                .font(.system(.body, design: .monospaced))
                            Button(action: { viewModel.copyServerURL() }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy URL")
                        }
                        
                        // Uptime (refreshes every second via timer)
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Uptime:")
                                .foregroundStyle(.secondary)
                            // Use uptimeRefreshTrigger to force refresh
                            let _ = uptimeRefreshTrigger
                            Text(viewModel.uptime)
                                .monospacedDigit()
                        }
                    } else {
                        // Port config
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Port:")
                                .foregroundStyle(.secondary)
                            Text("\(viewModel.configuration.port)")
                        }
                        
                        // Auth status
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Auth:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.configuration.requiresAuth ? "Enabled" : "Disabled")
                        }
                        
                        // Remote status
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Remote:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.configuration.allowRemoteConnections ? "Enabled" : "Disabled")
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.showSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
                .font(.callout)
                
                // API Key (if auth enabled)
                if viewModel.configuration.requiresAuth {
                    Divider()
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("API Key:")
                            .foregroundStyle(.secondary)
                        Text(String(repeating: "*", count: 8))
                            .font(.system(.body, design: .monospaced))
                        Button(action: { viewModel.copyAPIKey() }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy API Key")
                    }
                    .font(.callout)
                }
            }
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.vertical, DesignSystem.Padding.lg3)
        } label: {
            Text("Server Status")
                .font(.headline)
                .padding(.bottom, DesignSystem.Padding.xs)
        }
        .onReceive(uptimeTimer) { _ in
            if viewModel.isRunning {
                uptimeRefreshTrigger.toggle()
            }
        }
    }
}

// MARK: - Request Log Section

struct RequestLogSection: View {
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        GroupBox {
            if viewModel.requestLog.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No requests yet")
                        .foregroundStyle(.secondary)
                    if viewModel.isRunning {
                        Text("Incoming API requests will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Time")
                            .frame(width: 70, alignment: .leading)
                        Text("Method")
                            .frame(width: 60, alignment: .leading)
                        Text("Path")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Status")
                            .frame(width: 50, alignment: .center)
                        Text("Duration")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSystem.Padding.md)
                    .padding(.vertical, DesignSystem.Padding.sm2)
                    
                    Divider()
                    
                    // Log entries
                    ForEach(viewModel.requestLog) { entry in
                        RequestLogRow(entry: entry)
                        
                        if entry.id != viewModel.requestLog.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Request Log")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.requestLog.isEmpty {
                    Button("Clear") {
                        viewModel.clearRequestLog()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}

// MARK: - Request Log Row

struct RequestLogRow: View {
    let entry: RequestLogEntry
    
    var body: some View {
        HStack(spacing: 0) {
            // Time
            Text(entry.timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            // Method (HOOK for webhooks, otherwise HTTP method)
            Text(entry.method)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 60, alignment: .leading)
            
            // Path (webhook URL or API path)
            Text(entry.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status (with retry count for webhooks)
            if entry.isWebhook {
                HStack(spacing: 2) {
                    if entry.statusCode > 0 {
                        Text("\(entry.statusCode)")
                    } else {
                        Text("ERR")
                    }
                    if let attempts = entry.webhookAttempts, attempts > 1 {
                        Text("(\(attempts)x)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(webhookStatusColor)
                .frame(width: 80, alignment: .center)
            } else {
                Text("\(entry.statusCode)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .frame(width: 50, alignment: .center)
            }
            
            // Duration (or error indicator for webhooks)
            if entry.isWebhook {
                if entry.webhookError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(entry.webhookError ?? "")
                        .frame(width: 70, alignment: .trailing)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 70, alignment: .trailing)
                }
            } else {
                Text(entry.durationString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.xs)
        .background(entry.isWebhook ? Color.purple.opacity(0.05) : Color.clear)
    }
    
    var methodColor: Color {
        if entry.isWebhook {
            return .purple
        }
        switch entry.method {
        case "GET": return .blue
        case "POST": return .green
        case "DELETE": return .red
        case "PUT", "PATCH": return .orange
        default: return .primary
        }
    }
    
    var statusColor: Color {
        switch entry.statusCategory {
        case .success: return .green
        case .clientError: return .orange
        case .serverError: return .red
        case .other: return .secondary
        }
    }
    
    var webhookStatusColor: Color {
        if entry.webhookError != nil {
            return .orange
        }
        return .green
    }
}

// MARK: - Active Jobs Section

struct ActiveJobsSection: View {
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        GroupBox {
            if viewModel.activeJobs.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No active jobs")
                        .foregroundStyle(.secondary)
                    if !viewModel.isRunning {
                        Text("Start the server to accept analysis requests")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(viewModel.activeJobs) { job in
                        ActiveJobCard(job: job, onCancel: {
                            viewModel.cancelJob(job.id)
                        })
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Active Jobs")
                    .font(.headline)
                if !viewModel.activeJobs.isEmpty {
                    Text("(\(viewModel.activeJobs.count))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}

// MARK: - Active Job Card

struct ActiveJobCard: View {
    let job: AnalysisJob
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text(job.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            // Source and time
            HStack {
                Text("Source: \(job.source.rawValue.capitalized)")
                Text("*")
                if let started = job.startedAt {
                    Text("Started: \(started, style: .relative) ago")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            // Progress bar
            HStack {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                
                Text("\(Int(job.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            
            // Phase status
            if let phase = job.currentPhase {
                Text(phase.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Phase indicators
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(AnalysisPhase.allCases, id: \.self) { phase in
                    if let status = job.phaseStatuses[phase], status != .skipped {
                        PhaseIndicator(phase: phase, status: status)
                    }
                }
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}

// MARK: - Phase Indicator

struct PhaseIndicator: View {
    let phase: AnalysisPhase
    let status: JobPhaseStatus
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            statusIcon
            Text(phase.rawValue.prefix(3).uppercased())
                .font(.caption2)
        }
        .foregroundStyle(statusColor)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
        case .pending:
            Image(systemName: "circle")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        case .skipped:
            EmptyView()
        }
    }
    
    var statusColor: Color {
        switch status {
        case .complete: return .green
        case .processing: return .blue
        case .pending: return .secondary
        case .failed: return .red
        case .skipped: return .clear
        }
    }
}

// MARK: - Job History Section

struct JobHistorySection: View {
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        GroupBox {
            if viewModel.completedJobs.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No job history")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.completedJobs) { job in
                        JobHistoryRow(job: job, viewModel: viewModel)
                        
                        if job.id != viewModel.completedJobs.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Job History")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.completedJobs.isEmpty {
                    Button("Clear") {
                        viewModel.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}

// MARK: - Job History Row

struct JobHistoryRow: View {
    let job: CompletedJob
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Status icon
            statusIcon
                .frame(width: 20)
            
            // File name
            Text(job.fileName)
                .lineLimit(1)
            
            Spacer()
            
            // Duration
            Text(job.durationFormatted)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 60, alignment: .trailing)
            
            // Relative time
            Text(job.relativeTimeString)
                .foregroundStyle(.tertiary)
                .font(.callout)
                .frame(width: 80, alignment: .trailing)
            
            // Actions - fixed width container for alignment
            HStack(spacing: DesignSystem.Spacing.sm3) {
                if job.status == .complete {
                    Button("JSON") {
                        viewModel.viewResult(jobId: job.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Open") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: job.filePath))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if job.status == .failed {
                    Button("Error") {
                        viewModel.errorMessage = job.error ?? "Unknown error"
                        viewModel.showError = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, DesignSystem.Padding.sm2)
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch job.status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - API Documentation View

struct APIDocumentationView: View {
    @ObservedObject var viewModel: ServerViewModel
    @State private var copiedEndpoint: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl2) {
                // Quick start info (only shown when server is running)
                if viewModel.isRunning {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Server is running at \(viewModel.serverURL)")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("Use the endpoints below to analyze files via the REST API.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DesignSystem.Padding.lg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                }
                
                // Endpoints Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        EndpointRow(
                            method: "POST",
                            path: "/analyze/path",
                            description: "Analyze a video file by path (with optional webhook callback)",
                            example: """
                            {
                              "path": "/path/to/video.mp4",
                              "options": { "info": true, "bitrate": true },
                              "webhook": {
                                "url": "https://example.com/callback",
                                "headers": { "Authorization": "Bearer token" }
                              }
                            }
                            """,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                        
                        Divider().padding(.vertical, DesignSystem.Padding.lg)
                        
                        EndpointRow(
                            method: "GET",
                            path: "/jobs",
                            description: "List all active and recent jobs",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                        
                        Divider().padding(.vertical, DesignSystem.Padding.lg)
                        
                        EndpointRow(
                            method: "GET",
                            path: "/jobs/{id}",
                            description: "Get job status and full analysis results",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                        
                        Divider().padding(.vertical, DesignSystem.Padding.lg)
                        
                        EndpointRow(
                            method: "DELETE",
                            path: "/jobs/{id}",
                            description: "Cancel a running job",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                        
                        Divider().padding(.vertical, DesignSystem.Padding.lg)
                        
                        EndpointRow(
                            method: "GET",
                            path: "/health",
                            description: "Health check endpoint",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                        
                        Divider().padding(.vertical, DesignSystem.Padding.lg)
                        
                        EndpointRow(
                            method: "GET",
                            path: "/info",
                            description: "Server capabilities and version info",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                    }
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                } label: {
                    Text("Endpoints")
                        .font(.headline)
                        .padding(.bottom, DesignSystem.Padding.xs)
                }
                
                // Analysis Options Section
                GroupBox {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Include these in the request body's `options` object:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: DesignSystem.Spacing.md2) {
                            OptionBadge(name: "info", description: "Metadata")
                            OptionBadge(name: "bitrate", description: "Bitrate graph")
                            OptionBadge(name: "gop", description: "GOP structure")
                            OptionBadge(name: "waveform", description: "Audio waveform")
                            OptionBadge(name: "sync", description: "A/V sync")
                            OptionBadge(name: "keyframes", description: "Keyframe list")
                            OptionBadge(name: "color", description: "Color analysis")
                            OptionBadge(name: "all", description: "All analyses")
                        }
                    }
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                } label: {
                    Text("Analysis Options")
                        .font(.headline)
                        .padding(.bottom, DesignSystem.Padding.xs)
                }
            }
            .padding(DesignSystem.Padding.lg3)
        }
    }
}

// MARK: - Endpoint Row

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String
    let example: String?
    let baseURL: String
    @Binding var copiedEndpoint: String?
    
    @State private var showExample: Bool = false
    
    var methodColor: Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "DELETE": return .red
        case "PUT", "PATCH": return .orange
        default: return .secondary
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Method badge
                Text(method)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 54)
                    .padding(.vertical, DesignSystem.Padding.xs)
                    .background(methodColor)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                
                // Path
                Text(path)
                    .font(.system(.callout, design: .monospaced))
                
                Spacer()
                
                // Buttons container - fixed width for alignment
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Copy button
                    Button(action: copyEndpoint) {
                        if copiedEndpoint == path {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy full URL")
                    
                    // Example toggle (visible only if example exists, but space always reserved)
                    Button(action: { withAnimation { showExample.toggle() } }) {
                        Image(systemName: showExample ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show example")
                    .opacity(example != nil ? 1 : 0)
                    .disabled(example == nil)
                }
                .frame(width: 50, alignment: .trailing)
            }
            
            // Description
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Example code
            if showExample, let example = example {
                Text(example)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(DesignSystem.Padding.md2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
        }
    }
    
    private func copyEndpoint() {
        let fullURL = baseURL + path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullURL, forType: .string)
        
        copiedEndpoint = path
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedEndpoint == path {
                copiedEndpoint = nil
            }
        }
    }
}

// MARK: - Option Badge

struct OptionBadge: View {
    let name: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Server Settings Sheet

struct ServerSettingsSheet: View {
    @ObservedObject var viewModel: ServerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var port: Int
    @State private var enableAuth: Bool
    @State private var allowRemote: Bool
    
    init(viewModel: ServerViewModel) {
        self.viewModel = viewModel
        _port = State(initialValue: viewModel.configuration.port)
        _enableAuth = State(initialValue: viewModel.configuration.enableAuth)
        _allowRemote = State(initialValue: viewModel.configuration.allowRemoteConnections)
    }
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Text("Server Settings")
                .font(.headline)
            
            Form {
                Section {
                    TextField("Port:", value: $port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                Section {
                    Toggle("Enable Authentication", isOn: $enableAuth)
                        .disabled(allowRemote) // Required if remote enabled
                    
                    Toggle("Allow Remote Connections", isOn: $allowRemote)
                        .onChange(of: allowRemote) { _, newValue in
                            if newValue {
                                enableAuth = true
                            }
                        }
                    
                    if allowRemote {
                        Text("Warning: Enabling remote connections exposes the server to the network.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                if enableAuth {
                    Section("API Key") {
                        HStack {
                            Text(viewModel.apiKey)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Spacer()
                            
                            Button("Regenerate") {
                                viewModel.regenerateAPIKey()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            if viewModel.isRunning {
                Text("Changes require server restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    viewModel.updatePort(port)
                    viewModel.updateAllowRemote(allowRemote)
                    viewModel.updateEnableAuth(enableAuth)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .frame(width: 400)
    }
}

// MARK: - Job Result Sheet

struct JobResultSheet: View {
    @ObservedObject var viewModel: ServerViewModel
    let jobId: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg3) {
            HStack {
                Text("Analysis Result")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let json = viewModel.getResultJSON(for: jobId) {
                ScrollView {
                    Text(json)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(DesignSystem.CornerRadius.medium)
                
                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                    }
                    
                    Button("Save as JSON...") {
                        saveJSON(json)
                    }
                    
                    Spacer()
                    
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            } else {
                Text("No result available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .frame(width: 700, height: 500)
    }
    
    private func saveJSON(_ json: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "analysis_result.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

#Preview {
    ServerTabView()
}
