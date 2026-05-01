import Foundation
import CryptoKit
import Observation

// MARK: - Cache Configuration

private enum CacheConfig {
    static let version = 1
    static let waveformVersion = 4 // Bumped - new Accelerate-based waveform extractor
    static let maxCacheSizeBytes: Int64 = 1_073_741_824 // 1 GB
    static let cacheDirectoryName = "FramePeek"
    static let waveformSubdirectory = "Waveforms"
    static let gopSubdirectory = "GOPAnalysis"
    static let gopFrameDetailSubdirectory = "GOPFrameDetails"
    static let waveformFileExtension = "waveform"
    static let gopFileExtension = "gop"
    static let gopFrameDetailExtension = "gopframes"
}

// MARK: - Generic In-Memory LRU

/// Bounded in-memory LRU cache. Most-recently-used at the tail of `accessOrder`.
public struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be positive")
        self.capacity = capacity
    }

    public var keys: Dictionary<Key, Value>.Keys { storage.keys }

    public mutating func get(_ key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        promote(key)
        return value
    }

    public mutating func set(_ key: Key, _ value: Value) {
        storage[key] = value
        promote(key)
        while accessOrder.count > capacity {
            let evicted = accessOrder.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public mutating func removeAll() {
        storage.removeAll()
        accessOrder.removeAll()
    }

    private mutating func promote(_ key: Key) {
        if let existingIndex = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: existingIndex)
        }
        accessOrder.append(key)
    }
}

// MARK: - Cached Data Structures

public struct CachedWaveformData: Codable {
    public let version: Int
    public let samples: [WaveformSample]
    public let isPartial: Bool
    public let partialDurationSeconds: Double?
    public let createdAt: Date
}

public struct CachedGOPData: Codable {
    public let version: Int
    public let segments: [CachedGOPSegment]
    public let isPartial: Bool
    public let partialDurationSeconds: Double?
    public let createdAt: Date
    // Additional fields for full GOPAnalysisResult reconstruction
    public let isPreview: Bool
    public let scannedUntilSeconds: Double
    public let structureType: GOPStructureType
    public let representativeGOPIndex: Int?  // Index into segments array
}

/// Simplified GOP segment for caching (without non-Codable properties)
public struct CachedGOPSegment: Codable {
    public let startTime: Double
    public let endTime: Double
    public let frameCount: Int?
    public let frames: [CachedFrameInfo]?
}

/// Per-GOP frame detail cache (lightweight, keyed by video hash + segment time range)
public struct CachedGOPFrameDetails: Codable {
    public let version: Int
    public let segmentStartTime: Double
    public let segmentEndTime: Double
    public let frames: [CachedFrameInfo]
    public let createdAt: Date
}

public struct CachedFrameInfo: Codable {
    public let time: Double
    public let type: String // "I", "P", "B", "?"
    public let size: Int64?
}

// MARK: - Cache Manager

@MainActor
@Observable
public final class CacheManager {
    public static let shared = CacheManager()

    public private(set) var currentCacheSize: Int64 = 0
    public private(set) var isCalculatingSize: Bool = false

    private let fileManager = FileManager.default
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    private var cacheBaseURL: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(CacheConfig.cacheDirectoryName)
    }

    private var waveformCacheURL: URL? {
        cacheBaseURL?.appendingPathComponent(CacheConfig.waveformSubdirectory)
    }

    private var gopCacheURL: URL? {
        cacheBaseURL?.appendingPathComponent(CacheConfig.gopSubdirectory)
    }

    private var gopFrameDetailCacheURL: URL? {
        cacheBaseURL?.appendingPathComponent(CacheConfig.gopFrameDetailSubdirectory)
    }

    private init() {
        createCacheDirectoriesIfNeeded()
        Task {
            await recalculateCacheSize()
        }
    }

    // MARK: - Directory Management

    private func createCacheDirectoriesIfNeeded() {
        guard let waveformURL = waveformCacheURL,
              let gopURL = gopCacheURL,
              let gopFrameDetailURL = gopFrameDetailCacheURL else { return }

        try? fileManager.createDirectory(at: waveformURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: gopURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: gopFrameDetailURL, withIntermediateDirectories: true)
    }

    // MARK: - Cache Key Generation

    /// Generate a unique cache key based on file path, modification date, size, and cache version
    /// For waveform caches, use waveformVersion to allow separate invalidation
    public func cacheKey(for url: URL, useWaveformVersion: Bool = false) async -> String? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modDate = resourceValues.contentModificationDate,
                  let fileSize = resourceValues.fileSize else {
                return nil
            }

            let version = useWaveformVersion ? CacheConfig.waveformVersion : CacheConfig.version
            let input = "\(url.path)|\(modDate.timeIntervalSince1970)|\(fileSize)|\(version)"
            let hash = SHA256.hash(data: Data(input.utf8))
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    // MARK: - Waveform Cache

    public func loadWaveformCache(for url: URL) async -> CachedWaveformData? {
        guard let key = await cacheKey(for: url, useWaveformVersion: true),
              let cacheURL = waveformCacheURL else { return nil }

        let fileURL = cacheURL.appendingPathComponent("\(key).\(CacheConfig.waveformFileExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try decoder.decode(CachedWaveformData.self, from: data)

            // Version check
            guard cached.version == CacheConfig.waveformVersion else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }

            return cached
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    public func saveWaveformCache(
        for url: URL,
        samples: [WaveformSample],
        isPartial: Bool = false,
        partialDurationSeconds: Double? = nil
    ) async {
        guard let key = await cacheKey(for: url, useWaveformVersion: true),
              let cacheURL = waveformCacheURL else { return }

        let cached = CachedWaveformData(
            version: CacheConfig.waveformVersion,
            samples: samples,
            isPartial: isPartial,
            partialDurationSeconds: partialDurationSeconds,
            createdAt: Date.now
        )

        let fileURL = cacheURL.appendingPathComponent("\(key).\(CacheConfig.waveformFileExtension)")

        do {
            let data = try encoder.encode(cached)
            try data.write(to: fileURL)
            await enforceCacheSizeLimit()
            await recalculateCacheSize()
        } catch {
            // Cache write failed - not critical
        }
    }

    // MARK: - GOP Cache

    public func loadGOPCache(for url: URL) async -> CachedGOPData? {
        guard let key = await cacheKey(for: url),
              let cacheURL = gopCacheURL else { return nil }

        let fileURL = cacheURL.appendingPathComponent("\(key).\(CacheConfig.gopFileExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try decoder.decode(CachedGOPData.self, from: data)

            // Version check
            guard cached.version == CacheConfig.version else {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }

            return cached
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    public func saveGOPCache(
        for url: URL,
        segments: [GOPSegment],
        isPartial: Bool = false,
        partialDurationSeconds: Double? = nil,
        isPreview: Bool = false,
        scannedUntilSeconds: Double = 0,
        structureType: GOPStructureType = .unknown,
        representativeGOPIndex: Int? = nil
    ) async {
        guard let key = await cacheKey(for: url),
              let cacheURL = gopCacheURL else { return }

        // Convert to cacheable format
        let cachedSegments = segments.map { segment in
            CachedGOPSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                frameCount: segment.frameCount,
                frames: segment.frames?.map { frame in
                    CachedFrameInfo(time: frame.time, type: frame.type.rawValue, size: frame.size)
                }
            )
        }

        let cached = CachedGOPData(
            version: CacheConfig.version,
            segments: cachedSegments,
            isPartial: isPartial,
            partialDurationSeconds: partialDurationSeconds,
            createdAt: Date.now,
            isPreview: isPreview,
            scannedUntilSeconds: scannedUntilSeconds,
            structureType: structureType,
            representativeGOPIndex: representativeGOPIndex
        )

        let fileURL = cacheURL.appendingPathComponent("\(key).\(CacheConfig.gopFileExtension)")

        do {
            let data = try encoder.encode(cached)
            try data.write(to: fileURL)
            await enforceCacheSizeLimit()
            await recalculateCacheSize()
        } catch {
            // Cache write failed - not critical
        }
    }

    // MARK: - GOP Frame Detail Cache

    /// Generate a cache key for a specific GOP segment within a video file
    private func gopFrameDetailKey(videoKey: String, startTime: Double, endTime: Double) -> String {
        let timeKey = String(format: "%.4f_%.4f", startTime, endTime)
        return "\(videoKey)_\(timeKey)"
    }

    /// Load cached frame details for a specific GOP segment
    public func loadGOPFrameDetails(for url: URL, startTime: Double, endTime: Double) async -> [FrameInfo]? {
        guard let cacheURL = gopFrameDetailCacheURL,
              let key = await cacheKey(for: url) else { return nil }

        let detailKey = gopFrameDetailKey(videoKey: key, startTime: startTime, endTime: endTime)
        let fileURL = cacheURL.appendingPathComponent("\(detailKey).\(CacheConfig.gopFrameDetailExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let cached = try decoder.decode(CachedGOPFrameDetails.self, from: data)
            guard cached.version == CacheConfig.version else { return nil }

            return cached.frames.map { cachedFrame in
                FrameInfo(
                    time: cachedFrame.time,
                    type: FrameType(rawValue: cachedFrame.type) ?? .unknown,
                    size: cachedFrame.size
                )
            }
        } catch {
            return nil
        }
    }

    /// Save frame details for a specific GOP segment to disk
    public func saveGOPFrameDetails(for url: URL, startTime: Double, endTime: Double, frames: [FrameInfo]) async {
        guard let cacheURL = gopFrameDetailCacheURL,
              let key = await cacheKey(for: url) else { return }

        let detailKey = gopFrameDetailKey(videoKey: key, startTime: startTime, endTime: endTime)
        let fileURL = cacheURL.appendingPathComponent("\(detailKey).\(CacheConfig.gopFrameDetailExtension)")

        let cached = CachedGOPFrameDetails(
            version: CacheConfig.version,
            segmentStartTime: startTime,
            segmentEndTime: endTime,
            frames: frames.map { CachedFrameInfo(time: $0.time, type: $0.type.rawValue, size: $0.size) },
            createdAt: Date()
        )

        do {
            let data = try encoder.encode(cached)
            try data.write(to: fileURL)
            await enforceCacheSizeLimit()
            await recalculateCacheSize()
        } catch {
            // Cache write failed - not critical
        }
    }

    /// Convert cached GOP data back to GOPSegment array
    public func convertCachedGOPSegments(_ cached: [CachedGOPSegment]) -> [GOPSegment] {
        cached.map { cachedSegment in
            GOPSegment(
                startTime: cachedSegment.startTime,
                endTime: cachedSegment.endTime,
                frameCount: cachedSegment.frameCount,
                frames: cachedSegment.frames?.map { cachedFrame in
                    FrameInfo(
                        time: cachedFrame.time,
                        type: FrameType(rawValue: cachedFrame.type) ?? .unknown,
                        size: cachedFrame.size
                    )
                }
            )
        }
    }

    // MARK: - Cache Size Management

    public func recalculateCacheSize() async {
        isCalculatingSize = true
        defer { isCalculatingSize = false }

        var totalSize: Int64 = 0

        if let waveformURL = waveformCacheURL {
            totalSize += calculateDirectorySize(at: waveformURL)
        }

        if let gopURL = gopCacheURL {
            totalSize += calculateDirectorySize(at: gopURL)
        }

        if let gopFrameDetailURL = gopFrameDetailCacheURL {
            totalSize += calculateDirectorySize(at: gopFrameDetailURL)
        }

        currentCacheSize = totalSize
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }

    private func enforceCacheSizeLimit() async {
        guard let waveformURL = waveformCacheURL,
              let gopURL = gopCacheURL,
              let gopFrameDetailURL = gopFrameDetailCacheURL else { return }

        let currentSize = await Task.detached { [fileManager] in
            var size: Int64 = 0
            size += Self.calculateDirectorySizeStatic(at: waveformURL, fileManager: fileManager)
            size += Self.calculateDirectorySizeStatic(at: gopURL, fileManager: fileManager)
            size += Self.calculateDirectorySizeStatic(at: gopFrameDetailURL, fileManager: fileManager)
            return size
        }.value

        guard currentSize > CacheConfig.maxCacheSizeBytes else { return }

        // Collect all cache files with their dates
        var allFiles: [(url: URL, date: Date, size: Int64)] = []

        for cacheURL in [waveformURL, gopURL, gopFrameDetailURL] {
            if let enumerator = fileManager.enumerator(
                at: cacheURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                       let date = values.contentModificationDate,
                       let size = values.fileSize {
                        allFiles.append((url: fileURL, date: date, size: Int64(size)))
                    }
                }
            }
        }

        // Sort by date (oldest first)
        allFiles.sort { $0.date < $1.date }

        // Remove oldest files until under limit
        var remainingSize = currentSize
        let targetSize = CacheConfig.maxCacheSizeBytes * 9 / 10 // Target 90% of limit

        for file in allFiles {
            guard remainingSize > targetSize else { break }
            try? fileManager.removeItem(at: file.url)
            remainingSize -= file.size
        }
    }

    /// Static version for use in detached tasks
    private nonisolated static func calculateDirectorySizeStatic(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }

    // MARK: - Clear Cache

    public func clearAllCaches() async {
        if let waveformURL = waveformCacheURL {
            try? fileManager.removeItem(at: waveformURL)
        }
        if let gopURL = gopCacheURL {
            try? fileManager.removeItem(at: gopURL)
        }
        if let gopFrameDetailURL = gopFrameDetailCacheURL {
            try? fileManager.removeItem(at: gopFrameDetailURL)
        }

        createCacheDirectoriesIfNeeded()
        await recalculateCacheSize()
    }

    public func clearWaveformCache() async {
        if let waveformURL = waveformCacheURL {
            try? fileManager.removeItem(at: waveformURL)
            try? fileManager.createDirectory(at: waveformURL, withIntermediateDirectories: true)
        }
        await recalculateCacheSize()
    }

    public func clearGOPCache() async {
        if let gopURL = gopCacheURL {
            try? fileManager.removeItem(at: gopURL)
            try? fileManager.createDirectory(at: gopURL, withIntermediateDirectories: true)
        }
        if let gopFrameDetailURL = gopFrameDetailCacheURL {
            try? fileManager.removeItem(at: gopFrameDetailURL)
            try? fileManager.createDirectory(at: gopFrameDetailURL, withIntermediateDirectories: true)
        }
        await recalculateCacheSize()
    }

    // MARK: - Formatted Size

    public var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: currentCacheSize, countStyle: .file)
    }
}
