import Foundation

/// Protocol for reporting analysis progress
protocol ProgressReporter {
    func reportStart(file: String)
    func reportProgress(file: String, phase: String, percent: Double)
    func reportComplete(file: String)
    func reportError(file: String, error: Error)
}
