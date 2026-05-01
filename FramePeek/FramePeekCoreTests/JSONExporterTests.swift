import Testing
import Foundation
@testable import FramePeekCore

struct JSONExporterTests {

    private func makeResult() -> AnalysisResult {
        AnalysisResult(
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            file: FileInfo(path: "/x/y.mp4", name: "y.mp4", size: 1024, sizeFormatted: "1 KB"),
            metadata: nil,
            bitrate: nil,
            gop: nil,
            waveforms: nil,
            sync: nil,
            color: nil,
            keyframes: nil,
            thumbnails: nil
        )
    }

    @Test func resultRoundTripsThroughJSON() throws {
        let result = makeResult()
        let data = try JSONExporter.export(result)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnalysisResult.self, from: data)

        #expect(decoded.file.name == result.file.name)
        #expect(decoded.file.size == result.file.size)
        #expect(decoded.version == AnalysisResult.schemaVersion)
    }

    @Test func prettyPrintEmitsSortedKeys() throws {
        let result = makeResult()
        let pretty = try JSONExporter.exportString(result, prettyPrint: true)

        // Pretty printed output should contain newlines between keys
        #expect(pretty.contains("\n"))
        // Sorted keys means "analyzedAt" appears before "file" and "version"
        guard let analyzedAtIdx = pretty.range(of: "\"analyzedAt\"")?.lowerBound,
              let fileIdx = pretty.range(of: "\"file\"")?.lowerBound,
              let versionIdx = pretty.range(of: "\"version\"")?.lowerBound else {
            Issue.record("expected keys missing from pretty output")
            return
        }
        #expect(analyzedAtIdx < fileIdx)
        #expect(fileIdx < versionIdx)
    }

    @Test func exportMultipleProducesWrapper() throws {
        let results = [makeResult(), makeResult()]
        let data = try JSONExporter.exportMultiple(results)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MultiFileOutput.self, from: data)

        #expect(decoded.files.count == 2)
        #expect(decoded.version == AnalysisResult.schemaVersion)
    }
}
