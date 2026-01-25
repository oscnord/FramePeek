import Foundation

/// Silent progress reporter that outputs nothing
struct QuietProgressReporter: ProgressReporter {
    func reportStart(file: String) {}
    func reportProgress(file: String, phase: String, percent: Double) {}
    func reportComplete(file: String) {}
    func reportError(file: String, error: Error) {}
}
