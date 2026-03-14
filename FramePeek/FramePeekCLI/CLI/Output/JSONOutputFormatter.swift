import Foundation
import FramePeekCore

/// Formats analysis results as JSON
struct JSONOutputFormatter: OutputFormatter {
    let pretty: Bool
    
    func format(results: [FileAnalysisResult]) throws -> String {
        let output = CLIOutput(
            version: "1.0",
            generatedAt: ISO8601DateFormatter().string(from: Date.now),
            files: results.map { fileResult in
                CLIFileOutput(
                    path: fileResult.path,
                    error: fileResult.error,
                    metadata: fileResult.result?.metadata,
                    bitrate: fileResult.result?.bitrate,
                    gop: fileResult.result?.gop,
                    waveforms: fileResult.result?.waveforms,
                    sync: fileResult.result?.sync,
                    keyframes: fileResult.result?.keyframes
                )
            }
        )
        
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - CLI Output Models

struct CLIOutput: Codable {
    let version: String
    let generatedAt: String
    let files: [CLIFileOutput]
}

struct CLIFileOutput: Codable {
    let path: String
    let error: String?
    let metadata: ExtendedVideoInfo?
    let bitrate: BitrateAnalysisOutput?
    let gop: GOPAnalysisOutput?
    let waveforms: [String: [WaveformSampleOutput]]?
    let sync: SyncAnalysisOutput?
    let keyframes: [KeyframeOutput]?
}
