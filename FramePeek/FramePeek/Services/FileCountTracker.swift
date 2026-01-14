import Foundation

final class FileCountTracker {
    static let shared = FileCountTracker()
    
    private let fileCountKey = "processedFileCount"
    private let freeFileLimit = 3
    
    private init() {
    }
    
    func getFileCount() -> Int {
        return UserDefaults.standard.integer(forKey: fileCountKey)
    }
    
    func incrementFileCount() {
        let currentCount = getFileCount()
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: fileCountKey)
        UserDefaults.standard.synchronize()
    }
    
    func resetFileCount() {
        UserDefaults.standard.removeObject(forKey: fileCountKey)
    }
    
    func hasReachedLimit() -> Bool {
        return getFileCount() >= freeFileLimit
    }
    
    func getRemainingFreeFiles() -> Int {
        let count = getFileCount()
        return max(0, freeFileLimit - count)
    }
}



