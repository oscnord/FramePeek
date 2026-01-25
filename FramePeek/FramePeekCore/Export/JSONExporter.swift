import Foundation

/// Utility for exporting analysis results to JSON
public struct JSONExporter {
    
    /// JSON encoder configured for CLI output
    public static func makeEncoder(prettyPrint: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }
    
    /// Exports a single analysis result to JSON data
    public static func export(_ result: AnalysisResult, prettyPrint: Bool = false) throws -> Data {
        let encoder = makeEncoder(prettyPrint: prettyPrint)
        return try encoder.encode(result)
    }
    
    /// Exports a single analysis result to JSON string
    public static func exportString(_ result: AnalysisResult, prettyPrint: Bool = false) throws -> String {
        let data = try export(result, prettyPrint: prettyPrint)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONExporterError.encodingFailed
        }
        return string
    }
    
    /// Exports multiple analysis results to JSON data
    public static func exportMultiple(_ results: [AnalysisResult], prettyPrint: Bool = false) throws -> Data {
        let wrapper = MultiFileOutput(
            version: AnalysisResult.schemaVersion,
            generatedAt: Date(),
            files: results
        )
        let encoder = makeEncoder(prettyPrint: prettyPrint)
        return try encoder.encode(wrapper)
    }
    
    /// Exports multiple analysis results to JSON string
    public static func exportMultipleString(_ results: [AnalysisResult], prettyPrint: Bool = false) throws -> String {
        let data = try exportMultiple(results, prettyPrint: prettyPrint)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONExporterError.encodingFailed
        }
        return string
    }
    
    /// Writes analysis result to a file
    public static func write(_ result: AnalysisResult, to url: URL, prettyPrint: Bool = false) throws {
        let data = try export(result, prettyPrint: prettyPrint)
        try data.write(to: url)
    }
    
    /// Writes multiple analysis results to a file
    public static func writeMultiple(_ results: [AnalysisResult], to url: URL, prettyPrint: Bool = false) throws {
        let data = try exportMultiple(results, prettyPrint: prettyPrint)
        try data.write(to: url)
    }
}

/// Error types for JSON export
public enum JSONExporterError: Error, LocalizedError {
    case encodingFailed
    case writeFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data to UTF-8 string"
        case .writeFailed(let error):
            return "Failed to write JSON file: \(error.localizedDescription)"
        }
    }
}

/// Wrapper for multiple file results
public struct MultiFileOutput: Codable, Sendable {
    public let version: String
    public let generatedAt: Date
    public let files: [AnalysisResult]
    
    public init(version: String, generatedAt: Date, files: [AnalysisResult]) {
        self.version = version
        self.generatedAt = generatedAt
        self.files = files
    }
}
