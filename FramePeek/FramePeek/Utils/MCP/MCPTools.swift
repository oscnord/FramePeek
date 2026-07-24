import Foundation

enum MCPToolError: LocalizedError {
    case unknownTool
    case invalidArguments(String)
    case fileNotFound(String)
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool: return "Unknown tool"
        case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .analysisFailed(let detail): return "Analysis failed: \(detail)"
        }
    }
}

enum MCPTools {

    static let analysisKinds = ["metadata", "bitrate", "gop", "waveform", "sync", "keyframes", "color", "loudness"]

    static var definitions: [JSONValue] {
        [analyzeMediaDefinition, mediaSummaryDefinition, inspectContainerDefinition]
    }

    private static let pathProperty: JSONValue = .object([
        "type": .string("string"),
        "description": .string("Absolute path to the media file"),
    ])

    private static let analyzeMediaDefinition: JSONValue = .object([
                "name": .string("analyze_media"),
                "description": .string("Run selected analyses on a local media file and return the full structured result (metadata, per-second bitrate samples, GOP structure, audio waveforms, A/V sync, keyframe times, color, EBU R128 loudness)."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": pathProperty,
                        "include": .object([
                            "type": .string("array"),
                            "items": .object([
                                "type": .string("string"),
                                "enum": .array(analysisKinds.map { .string($0) }),
                            ]),
                            "description": .string("Analyses to run; defaults to [\"metadata\"]"),
                        ]),
                        "max_samples": .object([
                            "type": .string("number"),
                            "description": .string("Maximum bitrate samples (1-20000, default 2000)"),
                        ]),
                    ]),
                    "required": .array([.string("path")]),
                ]),
            ])

    private static let mediaSummaryDefinition: JSONValue = .object([
        "name": .string("media_summary"),
        "description": .string("Cheap first call: container, codec and profile, resolution, frame rate, duration, HDR format, audio tracks, and overall bitrate of a local media file."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object(["path": pathProperty]),
            "required": .array([.string("path")]),
        ]),
    ])

    private static let inspectContainerDefinition: JSONValue = .object([
        "name": .string("inspect_container"),
        "description": .string("Parse the MP4/MOV/CMAF atom tree of a local media file: fourCC, size, and offset per box, nested children capped at 50 per node."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object(["path": pathProperty]),
            "required": .array([.string("path")]),
        ]),
    ])

    static func call(name: String, arguments: JSONValue) async -> Result<String, Error> {
        do {
            switch name {
            case "analyze_media": return .success(try await analyzeMedia(arguments))
            case "media_summary": return .success(try await mediaSummary(arguments))
            case "inspect_container": return .success(try await inspectContainer(arguments))
            default: return .failure(MCPToolError.unknownTool)
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Tools

    private struct AnalyzeMediaParams: Decodable {
        let path: String
        let include: [String]?
        let max_samples: Int?
    }

    private static func analyzeMedia(_ arguments: JSONValue) async throws -> String {
        let params: AnalyzeMediaParams = try decode(arguments)
        let url = try validatedFileURL(params.path)

        let include = Set(params.include ?? ["metadata"])
        if let unknown = include.first(where: { !analysisKinds.contains($0) }) {
            throw MCPToolError.invalidArguments("Unknown analysis kind \"\(unknown)\"; expected one of \(analysisKinds.joined(separator: ", "))")
        }

        let options = AnalysisOptions(
            includeMetadata: include.contains("metadata"),
            includeBitrate: include.contains("bitrate"),
            includeGOP: include.contains("gop"),
            includeWaveform: include.contains("waveform"),
            includeSync: include.contains("sync"),
            includeColor: include.contains("color"),
            includeKeyframes: include.contains("keyframes"),
            includeLoudness: include.contains("loudness"),
            maxSamples: min(max(params.max_samples ?? 2000, 1), 20_000)
        )

        do {
            let result = try await AnalysisEngine().analyze(url: url, options: options)
            return try encodeJSON(result)
        } catch {
            throw MCPToolError.analysisFailed(error.localizedDescription)
        }
    }

    private struct PathParams: Decodable {
        let path: String
    }

    private struct MediaSummary: Encodable {
        let container: String?
        let codec: String
        let codecProfile: String?
        let resolution: String
        let frameRate: String
        let durationSeconds: Double?
        let hdrFormat: String?
        let overallBitrate: String
        let audioTracks: [AudioSummary]

        struct AudioSummary: Encodable {
            let codec: String
            let channels: Int
            let channelLayout: String
            let sampleRateHz: Double
            let language: String?
        }
    }

    private static func mediaSummary(_ arguments: JSONValue) async throws -> String {
        let params: PathParams = try decode(arguments)
        let url = try validatedFileURL(params.path)

        let result: AnalysisResult
        do {
            result = try await AnalysisEngine().analyze(url: url, options: AnalysisOptions(includeMetadata: true))
        } catch {
            throw MCPToolError.analysisFailed(error.localizedDescription)
        }
        guard let info = result.metadata else {
            throw MCPToolError.analysisFailed("No metadata could be extracted")
        }

        let summary = MediaSummary(
            container: info.containerFormat,
            codec: info.codec,
            codecProfile: info.codecProfile,
            resolution: info.resolution,
            frameRate: info.frameRate,
            durationSeconds: Double(info.duration.split(separator: " ").first.map(String.init) ?? ""),
            hdrFormat: info.hdrFormat,
            overallBitrate: info.overallBitrate,
            audioTracks: info.audioTracks.map {
                MediaSummary.AudioSummary(
                    codec: $0.codec,
                    channels: $0.channels,
                    channelLayout: $0.channelLayout,
                    sampleRateHz: $0.sampleRateHz,
                    language: $0.languageCode
                )
            }
        )
        return try encodeJSON(summary)
    }

    private struct AtomSummary: Encodable {
        let fourCC: String
        let size: UInt64
        let offset: UInt64
        let children: [AtomSummary]
        let truncated: Bool
    }

    private struct ContainerSummary: Encodable {
        let format: String
        let fileSize: UInt64
        let isFragmented: Bool
        let atoms: [AtomSummary]
    }

    private static func inspectContainer(_ arguments: JSONValue) async throws -> String {
        let params: PathParams = try decode(arguments)
        let url = try validatedFileURL(params.path)

        guard let result = await ContainerParser.parse(url: url) else {
            throw MCPToolError.analysisFailed("Not a parseable MP4/MOV/CMAF container")
        }

        let summary = ContainerSummary(
            format: result.format.rawValue,
            fileSize: result.fileSize,
            isFragmented: result.isFragmented,
            atoms: result.atoms.map(summarize)
        )
        return try encodeJSON(summary)
    }

    private static func summarize(_ atom: ContainerAtom) -> AtomSummary {
        AtomSummary(
            fourCC: atom.fourCC,
            size: atom.size,
            offset: atom.offset,
            children: atom.children.prefix(50).map(summarize),
            truncated: atom.children.count > 50
        )
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ arguments: JSONValue) throws -> T {
        do {
            let data = try JSONEncoder().encode(arguments)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MCPToolError.invalidArguments(String(describing: error))
        }
    }

    private static func validatedFileURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw MCPToolError.invalidArguments("path must be absolute")
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw MCPToolError.fileNotFound(path)
        }
        return URL(fileURLWithPath: path)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPToolError.analysisFailed("Result could not be encoded as UTF-8")
        }
        return text
    }
}
