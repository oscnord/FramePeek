import Foundation

/// Reports progress to stderr for TTY output
struct TTYProgressReporter: ProgressReporter {
    let verbose: Bool
    private let stderr = FileHandle.standardError
    
    func reportStart(file: String) {
        write("Analyzing: \(file)\n")
    }
    
    func reportProgress(file: String, phase: String, percent: Double) {
        if verbose {
            let bar = progressBar(percent: percent)
            write("\r  \(phase): \(bar) \(Int(percent * 100))%")
        }
    }
    
    func reportComplete(file: String) {
        if verbose {
            write("\r" + String(repeating: " ", count: 60) + "\r")
        }
        write("  Complete: \(URL(fileURLWithPath: file).lastPathComponent)\n")
    }
    
    func reportError(file: String, error: Error) {
        write("  Error: \(error.localizedDescription)\n")
    }
    
    private func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            stderr.write(data)
        }
    }
    
    private func progressBar(percent: Double, width: Int = 30) -> String {
        let filled = Int(percent * Double(width))
        let empty = width - filled
        return "[" + String(repeating: "=", count: filled) + String(repeating: " ", count: empty) + "]"
    }
}
