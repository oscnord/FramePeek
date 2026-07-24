import Foundation
import os

public struct FPLogger: Sendable {
    private let logger: Logger

    fileprivate init(category: String) {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.framepeek.FramePeek"
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func notice(_ message: String) { logger.notice("\(message, privacy: .public)") }
    public func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    public func fault(_ message: String) { logger.fault("\(message, privacy: .public)") }
}

public enum Log {
    public static let analysis = FPLogger(category: "analysis")
    public static let parsing = FPLogger(category: "parsing")
    public static let media = FPLogger(category: "media")
    public static let server = FPLogger(category: "server")
    public static let cli = FPLogger(category: "cli")
    public static let ui = FPLogger(category: "ui")
}
