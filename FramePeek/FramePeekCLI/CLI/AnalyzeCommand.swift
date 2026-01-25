import Foundation
import ArgumentParser
import FramePeekCore

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze media files"
    )
    
    // MARK: - Arguments
    
    @Argument(help: "One or more media files to analyze")
    var files: [String] = []
    
    // MARK: - Analysis Selection Options
    
    @Flag(name: .shortAndLong, help: "Run all analyses")
    var all: Bool = false
    
    @Flag(name: [.customShort("i"), .long], help: "Metadata extraction (default if none specified)")
    var info: Bool = false
    
    @Flag(name: [.customShort("b"), .long], help: "Bitrate analysis")
    var bitrate: Bool = false
    
    @Flag(name: [.customShort("g"), .long], help: "GOP structure analysis")
    var gop: Bool = false
    
    @Flag(name: [.customShort("w"), .long], help: "Audio waveform extraction")
    var waveform: Bool = false
    
    @Flag(name: [.customShort("s"), .long], help: "A/V sync analysis")
    var sync: Bool = false
    
    @Flag(name: [.customShort("c"), .long], help: "Color analysis")
    var color: Bool = false
    
    @Flag(name: [.customShort("k"), .long], help: "List keyframe timestamps")
    var keyframes: Bool = false
    
    @Option(name: [.customShort("t"), .long], help: "Export thumbnails to directory")
    var thumbnails: String?
    
    // MARK: - Output Options
    
    @Option(name: [.customShort("f"), .long], help: "Output format: json (default), text, csv")
    var format: OutputFormat = .json
    
    @Option(name: [.customShort("o"), .long], help: "Output file (default: stdout)")
    var output: String?
    
    @Flag(name: .long, help: "Pretty-print JSON")
    var pretty: Bool = false
    
    @Flag(name: .long, help: "Minified JSON (no whitespace)")
    var compact: Bool = false
    
    // MARK: - Bitrate Options
    
    @Option(name: .long, help: "Bitrate mode: second, frame, gop")
    var bitrateMode: BitrateMode = .second
    
    @Flag(name: .long, help: "Use accurate but slower extraction")
    var preferAccuracy: Bool = false
    
    @Option(name: .long, help: "Maximum samples (default: 2000)")
    var maxSamples: Int = 2000
    
    // MARK: - GOP Options
    
    @Flag(name: .long, inversion: .prefixedNo, help: "Detect I/P/B frame types")
    var gopFrameTypes: Bool = true
    
    @Option(name: .long, help: "Limit GOP scan duration in seconds")
    var gopMaxSeconds: Double?
    
    @Flag(name: .long, help: "Output stats only, omit segment list")
    var gopStatsOnly: Bool = false
    
    // MARK: - Thumbnail Options
    
    @Option(name: .long, help: "Number of thumbnails (default: 10)")
    var thumbnailCount: Int = 10
    
    @Option(name: .long, help: "Thumbnail size: small, medium, large")
    var thumbnailSize: ThumbnailSizeOption = .medium
    
    // MARK: - Processing Options
    
    @Flag(name: .long, help: "Process multiple files concurrently")
    var parallel: Bool = false
    
    @Flag(name: .long, inversion: .prefixedNo, help: "Use cached results if available")
    var cache: Bool = true
    
    // MARK: - Verbosity Options
    
    @Flag(name: .shortAndLong, help: "Detailed progress to stderr")
    var verbose: Bool = false
    
    @Flag(name: .shortAndLong, help: "Suppress progress output")
    var quiet: Bool = false
    
    @Flag(name: .long, inversion: .prefixedNo, help: "Show progress bars")
    var progress: Bool = true
    
    // MARK: - Validation
    
    func validate() throws {
        if files.isEmpty {
            throw ValidationError("At least one file is required")
        }
        
        for file in files {
            let url = URL(fileURLWithPath: file)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw ValidationError("File not found: \(file)")
            }
        }
        
        if pretty && compact {
            throw ValidationError("Cannot use both --pretty and --compact")
        }
        
        if verbose && quiet {
            throw ValidationError("Cannot use both --verbose and --quiet")
        }
    }
    
    // MARK: - Run
    
    func run() async throws {
        let analysisOptions = buildAnalysisOptions()
        let progressReporter = buildProgressReporter()
        let outputFormatter = buildOutputFormatter()
        
        var results: [FileAnalysisResult] = []
        
        if parallel && files.count > 1 {
            // Process files concurrently
            results = await withTaskGroup(of: FileAnalysisResult.self) { group in
                for file in files {
                    group.addTask {
                        await analyzeFile(file, options: analysisOptions, progress: progressReporter)
                    }
                }
                
                var collected: [FileAnalysisResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
        } else {
            // Process files sequentially
            for file in files {
                let result = await analyzeFile(file, options: analysisOptions, progress: progressReporter)
                results.append(result)
            }
        }
        
        // Format and output results
        let output = try outputFormatter.format(results: results)
        
        if let outputPath = self.output {
            try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if !quiet {
                FileHandle.standardError.write("Results written to \(outputPath)\n".data(using: .utf8)!)
            }
        } else {
            print(output)
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildAnalysisOptions() -> AnalysisOptions {
        let includeInfo = all || info || (!bitrate && !gop && !waveform && !sync && !color && !keyframes && thumbnails == nil)
        
        return AnalysisOptions(
            includeMetadata: includeInfo,
            includeBitrate: all || bitrate,
            includeGOP: all || gop,
            includeWaveform: all || waveform,
            includeSync: all || sync,
            includeColor: all || color,
            includeKeyframes: all || keyframes,
            includeThumbnails: thumbnails != nil,
            bitrateMode: bitrateMode.toFramePeekCore(),
            preferAccuracy: preferAccuracy,
            maxSamples: maxSamples,
            gopDetectFrameTypes: gopFrameTypes,
            gopMaxScanSeconds: gopMaxSeconds,
            gopStatsOnly: gopStatsOnly,
            thumbnailCount: thumbnailCount,
            thumbnailSize: thumbnailSize.toFramePeekCore(),
            thumbnailOutputDirectory: thumbnails.map { URL(fileURLWithPath: $0) }
        )
    }
    
    private func buildProgressReporter() -> ProgressReporter {
        if quiet {
            return QuietProgressReporter()
        } else if verbose || (progress && isTerminal()) {
            return TTYProgressReporter(verbose: verbose)
        } else {
            return QuietProgressReporter()
        }
    }
    
    private func buildOutputFormatter() -> OutputFormatter {
        switch format {
        case .json:
            return JSONOutputFormatter(pretty: pretty || (!compact && isTerminal()))
        case .text:
            return TextOutputFormatter()
        case .csv:
            return CSVOutputFormatter()
        }
    }
    
    private func analyzeFile(_ path: String, options: AnalysisOptions, progress: ProgressReporter) async -> FileAnalysisResult {
        let url = URL(fileURLWithPath: path)
        let engine = AnalysisEngine()
        
        progress.reportStart(file: path)
        
        do {
            let result = try await engine.analyze(url: url, options: options)
            progress.reportComplete(file: path)
            return FileAnalysisResult(path: path, result: result, error: nil)
        } catch {
            progress.reportError(file: path, error: error)
            return FileAnalysisResult(path: path, result: nil, error: error.localizedDescription)
        }
    }
    
    private func isTerminal() -> Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }
}

// MARK: - Supporting Types

enum OutputFormat: String, ExpressibleByArgument {
    case json
    case text
    case csv
}

enum BitrateMode: String, ExpressibleByArgument {
    case second
    case frame
    case gop
    
    func toFramePeekCore() -> BitrateVisualizationMode {
        switch self {
        case .second: return .second
        case .frame: return .frame
        case .gop: return .gop
        }
    }
}

enum ThumbnailSizeOption: String, ExpressibleByArgument {
    case small
    case medium
    case large
    
    func toFramePeekCore() -> ThumbnailSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }
}

/// Result for a single file analysis
struct FileAnalysisResult {
    let path: String
    let result: AnalysisResult?
    let error: String?
}
