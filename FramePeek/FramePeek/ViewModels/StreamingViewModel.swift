import Foundation
import SwiftUI
import FramePeekCore
import UniformTypeIdentifiers

/// ViewModel for the Streaming (HLS ladder inspection) tab
@MainActor
@Observable
public final class StreamingViewModel {

    public var urlString: String = ""
    public var isAnalyzing: Bool = false
    public var progressMessage: String?
    public var result: StreamingLadderAnalysis?
    public var errorMessage: String?

    private var analysisTask: Task<Void, Never>?
    private var securityScopedFolder: URL?

    public init() {}

    public func analyzeFromURLField() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else {
            errorMessage = String(localized: "Enter an http(s) URL to a .m3u8 playlist")
            return
        }
        analyze(url: url)
    }

    /// Local playlists need folder-level access: a user-selected .m3u8 file
    /// grants sandbox access to that file only, not to sibling segments.
    public func openLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose the folder containing the HLS playlist and its segments")
        panel.prompt = String(localized: "Analyze")

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        guard let playlist = findPlaylist(in: folder) else {
            errorMessage = String(localized: "No .m3u8 playlist found in the selected folder")
            return
        }

        stopSecurityScope()
        if folder.startAccessingSecurityScopedResource() {
            securityScopedFolder = folder
        }
        urlString = playlist.path
        analyze(url: playlist)
    }

    public func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        progressMessage = nil
    }

    private func analyze(url: URL) {
        analysisTask?.cancel()
        errorMessage = nil
        result = nil
        isAnalyzing = true
        progressMessage = String(localized: "Loading playlist…")

        let task = Task {
            for await progress in analyzeHLSLadder(url: url) {
                guard !Task.isCancelled else { return }
                if let final = progress.result {
                    result = final
                } else {
                    progressMessage = progress.message
                }
            }
            guard !Task.isCancelled else { return }
            isAnalyzing = false
            progressMessage = nil
            stopSecurityScope()
        }
        analysisTask = task
    }

    /// Prefers the multivariant playlist when the folder holds several.
    private func findPlaylist(in folder: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        let playlists = contents
            .filter { $0.pathExtension.lowercased() == "m3u8" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let multivariant = playlists.first { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.contains("#EXT-X-STREAM-INF")
        }
        return multivariant ?? playlists.first
    }

    private func stopSecurityScope() {
        securityScopedFolder?.stopAccessingSecurityScopedResource()
        securityScopedFolder = nil
    }
}
