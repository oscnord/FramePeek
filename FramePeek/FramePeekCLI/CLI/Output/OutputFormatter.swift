import Foundation

/// Protocol for formatting analysis results
protocol OutputFormatter {
    func format(results: [FileAnalysisResult]) throws -> String
}
