//
//  RequestLog.swift
//  FramePeek
//
//  Created for FramePeek Server API
//

import Foundation

/// A single logged API request
public struct RequestLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let method: String
    public let path: String
    public let statusCode: Int
    public let duration: TimeInterval
    public let clientIP: String?
    public let isWebhook: Bool
    public let webhookAttempts: Int?
    public let webhookError: String?
    
    public init(
        method: String,
        path: String,
        statusCode: Int,
        duration: TimeInterval,
        clientIP: String? = nil,
        isWebhook: Bool = false,
        webhookAttempts: Int? = nil,
        webhookError: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.duration = duration
        self.clientIP = clientIP
        self.isWebhook = isWebhook
        self.webhookAttempts = webhookAttempts
        self.webhookError = webhookError
    }
    
    /// Formatted timestamp
    public var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// Formatted duration
    public var durationString: String {
        if duration < 0.001 {
            return "<1ms"
        } else if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }
    
    /// Status code category
    public var statusCategory: StatusCategory {
        switch statusCode {
        case 200..<300: return .success
        case 400..<500: return .clientError
        case 500..<600: return .serverError
        default: return .other
        }
    }
    
    public enum StatusCategory {
        case success
        case clientError
        case serverError
        case other
    }
}

/// Manages the request log with a fixed capacity
@MainActor
public final class RequestLogger: ObservableObject {
    @Published public private(set) var entries: [RequestLogEntry] = []
    
    public let maxEntries: Int
    
    public init(maxEntries: Int = 20) {
        self.maxEntries = maxEntries
    }
    
    /// Log a new request
    public func log(_ entry: RequestLogEntry) {
        entries.insert(entry, at: 0)
        
        // Trim to max entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
    
    /// Log a request with parameters
    public func log(
        method: String,
        path: String,
        statusCode: Int,
        duration: TimeInterval,
        clientIP: String? = nil
    ) {
        let entry = RequestLogEntry(
            method: method,
            path: path,
            statusCode: statusCode,
            duration: duration,
            clientIP: clientIP
        )
        log(entry)
    }
    
    /// Clear all entries
    public func clear() {
        entries.removeAll()
    }
    
    /// Log a webhook delivery attempt
    public func logWebhook(
        url: String,
        success: Bool,
        attempts: Int,
        statusCode: Int?,
        error: String?
    ) {
        let entry = RequestLogEntry(
            method: "HOOK",
            path: url,
            statusCode: statusCode ?? (success ? 200 : 0),
            duration: 0,
            clientIP: nil,
            isWebhook: true,
            webhookAttempts: attempts,
            webhookError: error
        )
        log(entry)
    }
}
