import Foundation

/// Manages the history of recently opened files
@MainActor
class FileHistoryManager: ObservableObject {
    static let shared = FileHistoryManager()
    
    private let maxHistoryCount = 10
    private let userDefaultsKey = "recentFileURLs"
    
    @Published private(set) var recentFiles: [URL] = []
    
    private init() {
        loadHistory()
    }
    
    /// Adds a file URL to the history
    func addFile(_ url: URL) {
        // Remove if already exists
        recentFiles.removeAll { $0 == url }
        
        // Add to beginning
        recentFiles.insert(url, at: 0)
        
        // Limit to max count
        if recentFiles.count > maxHistoryCount {
            recentFiles = Array(recentFiles.prefix(maxHistoryCount))
        }
        
        saveHistory()
    }
    
    /// Removes a file from history
    func removeFile(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        saveHistory()
    }
    
    /// Clears all history
    func clearHistory() {
        recentFiles.removeAll()
        saveHistory()
    }
    
    /// Checks if a file still exists at the stored path
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Returns only files that still exist
    var validFiles: [URL] {
        recentFiles.filter { fileExists(at: $0) }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let urls = try? JSONDecoder().decode([String].self, from: data) else {
            recentFiles = []
            return
        }
        
        recentFiles = urls.compactMap { URL(string: $0) }
            .filter { fileExists(at: $0) }
    }
    
    private func saveHistory() {
        let urlStrings = recentFiles.map { $0.absoluteString }
        if let data = try? JSONEncoder().encode(urlStrings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}



