import Foundation
import AVFoundation
import CoreMedia

// MARK: - Sync Sample Parser for MP4/MOV Files

/// Parses the `stss` (sync sample) atom from standard (non-fragmented) MP4/MOV files
/// to quickly identify keyframe positions without scanning the entire video stream.
/// This provides O(n) lookup for keyframe indices where n = number of keyframes.
///
/// **Supported formats**: Standard MP4, M4V, MOV (QuickTime)
///
/// **NOT supported (will return nil)**:
/// - Fragmented MP4 (fMP4) - keyframes stored in moof/traf/trun atoms
/// - CMAF - variant of fragmented MP4
/// - MPEG-TS - no stss atom
/// - All-intra codecs (ProRes, MJPEG, etc.) - no stss atom needed
///
/// MP4 box structure parsed:
/// ```
/// moov
///   └─ trak (video track)
///        └─ mdia
///             └─ minf
///                  └─ stbl
///                       ├─ stss (sync sample table - keyframe indices)
///                       └─ stts (time-to-sample - for timestamps)
/// ```
public enum SyncSampleParser {
    
    // MARK: - Types
    
    /// Result of parsing sync sample data
    public struct SyncSampleResult {
        /// 1-based indices of sync samples (keyframes)
        public let syncSampleIndices: [UInt32]
        /// Sample count to duration mappings from stts atom
        public let timeToSampleEntries: [(sampleCount: UInt32, sampleDuration: UInt32)]
        /// Total number of samples in the track
        public let totalSampleCount: UInt32
        /// Timescale for the track (from mdhd)
        public let timescale: UInt32
    }
    
    /// Parsed keyframe information with timestamps
    public struct KeyframeInfo {
        public let sampleIndex: UInt32  // 1-based
        public let timestamp: Double    // In seconds
    }
    
    /// Reasons why fast parsing might not be available
    public enum UnavailableReason {
        case unsupportedFormat          // Not MP4/MOV
        case fragmentedMP4              // fMP4/CMAF - needs different approach
        case noSyncSampleAtom           // All-intra codec (all frames are keyframes)
        case parseError                 // File structure couldn't be parsed
    }
    
    // MARK: - Public API
    
    /// Check if the file format potentially supports fast sync sample parsing
    /// Note: This only checks the extension. Use `parseSyncSamples` for definitive answer.
    /// - Parameter url: URL of the media file
    /// - Returns: True if the file extension suggests MP4/MOV format
    public static func canUseFastParsing(for url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov"].contains(ext)
    }
    
    /// Parse sync sample indices from an MP4/MOV file
    /// - Parameter url: URL of the media file
    /// - Returns: SyncSampleResult if successful, nil otherwise (fragmented, unsupported, or parse error)
    public static func parseSyncSamples(from url: URL) async -> SyncSampleResult? {
        guard canUseFastParsing(for: url) else { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? fileHandle.close() }
            
            // First, check if this is a fragmented MP4 by looking for moof atoms
            // If fragmented, we can't use the stss approach
            if isFragmentedMP4(fileHandle: fileHandle) {
                return nil
            }
            
            // Reset to beginning for moov search
            try? fileHandle.seek(toOffset: 0)
            
            // Find the moov atom
            guard let moovRange = findAtom(fourCC: "moov", in: fileHandle, searchRange: nil) else {
                return nil
            }
            
            // Find the video trak within moov
            guard let trakRange = findVideoTrack(in: fileHandle, moovRange: moovRange) else {
                return nil
            }
            
            // Find mdia within trak
            guard let mdiaRange = findAtom(fourCC: "mdia", in: fileHandle, searchRange: trakRange) else {
                return nil
            }
            
            // Get timescale from mdhd
            let timescale = parseMediaHeaderTimescale(in: fileHandle, mdiaRange: mdiaRange) ?? 90000
            
            // Find minf within mdia
            guard let minfRange = findAtom(fourCC: "minf", in: fileHandle, searchRange: mdiaRange) else {
                return nil
            }
            
            // Find stbl within minf
            guard let stblRange = findAtom(fourCC: "stbl", in: fileHandle, searchRange: minfRange) else {
                return nil
            }
            
            // Parse stss (sync sample table) - optional, some files may not have it
            // No stss means either: all-intra codec OR fragmented MP4
            let syncIndices = parseStssAtom(in: fileHandle, stblRange: stblRange)
            
            // If no stss found, this is likely an all-intra codec - can't use fast path
            // (we'd need to scan all frames anyway since they're all keyframes)
            guard let indices = syncIndices, !indices.isEmpty else {
                return nil
            }
            
            // Parse stts (time to sample)
            guard let sttsEntries = parseSttsAtom(in: fileHandle, stblRange: stblRange) else {
                return nil
            }
            
            // Calculate total sample count from stts
            var totalSamples: UInt32 = 0
            for entry in sttsEntries {
                totalSamples += entry.sampleCount
            }
            
            return SyncSampleResult(
                syncSampleIndices: indices,
                timeToSampleEntries: sttsEntries,
                totalSampleCount: totalSamples,
                timescale: timescale
            )
        }.value
    }
    
    /// Convert sync sample result to keyframe timestamps
    /// - Parameter result: The parsed sync sample result
    /// - Returns: Array of keyframe info with timestamps in seconds
    public static func keyframeTimestamps(from result: SyncSampleResult) -> [KeyframeInfo] {
        var keyframes: [KeyframeInfo] = []
        keyframes.reserveCapacity(result.syncSampleIndices.count)
        
        let timescale = Double(result.timescale)
        
        for syncIndex in result.syncSampleIndices {
            let timestamp = calculateTimestamp(
                forSampleIndex: syncIndex,
                sttsEntries: result.timeToSampleEntries,
                timescale: timescale
            )
            keyframes.append(KeyframeInfo(sampleIndex: syncIndex, timestamp: timestamp))
        }
        
        return keyframes
    }
    
    // MARK: - Fragmented MP4 Detection
    
    /// Check if the file is a fragmented MP4 (has moof atoms)
    private static func isFragmentedMP4(fileHandle: FileHandle) -> Bool {
        do {
            try fileHandle.seek(toOffset: 0)
            
            // Scan through top-level atoms looking for moof
            // We need to find at least the file type and check for moof presence
            var offset: UInt64 = 0
            let fileSize = fileHandle.seekToEndOfFile()
            try fileHandle.seek(toOffset: 0)
            
            // Limit scan to first 10MB to avoid scanning huge files
            let maxScanOffset = min(fileSize, 10 * 1024 * 1024)
            
            while offset < maxScanOffset {
                try fileHandle.seek(toOffset: offset)
                
                guard let headerData = try fileHandle.read(upToCount: 8),
                      headerData.count == 8 else { break }
                
                let size = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let typeData = headerData.subdata(in: 4..<8)
                let type = String(data: typeData, encoding: .ascii) ?? ""
                
                // Handle extended size
                var atomSize: UInt64
                if size == 1 {
                    guard let extSizeData = try fileHandle.read(upToCount: 8),
                          extSizeData.count == 8 else { break }
                    atomSize = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                } else if size == 0 {
                    atomSize = fileSize - offset
                } else {
                    atomSize = UInt64(size)
                }
                
                // Found moof = fragmented MP4
                if type == "moof" {
                    return true
                }
                
                // If we found moov before moof, it's likely standard MP4
                // But keep scanning a bit more to be sure
                if type == "mdat" && offset > 1024 * 1024 {
                    // Large mdat without moof seen = standard MP4
                    break
                }
                
                // Move to next atom
                if atomSize == 0 { break }
                offset += atomSize
            }
            
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Atom Finding
    
    /// Find an atom with the given FourCC code
    private static func findAtom(
        fourCC: String,
        in fileHandle: FileHandle,
        searchRange: Range<UInt64>?
    ) -> Range<UInt64>? {
        let targetFourCC = fourCC.data(using: .ascii)!
        
        let startOffset = searchRange?.lowerBound ?? 0
        let fileSize = fileHandle.seekToEndOfFile()
        let endOffset = searchRange?.upperBound ?? fileSize
        
        var currentOffset = startOffset
        
        while currentOffset < endOffset {
            do {
                try fileHandle.seek(toOffset: currentOffset)
                
                // Read atom header (8 bytes: 4 for size, 4 for type)
                guard let headerData = try fileHandle.read(upToCount: 8),
                      headerData.count == 8 else { break }
                
                let size = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let type = headerData.subdata(in: 4..<8)
                
                // Handle extended size (size == 1 means 64-bit size follows)
                var atomSize: UInt64
                var headerSize: UInt64 = 8
                
                if size == 1 {
                    guard let extSizeData = try fileHandle.read(upToCount: 8),
                          extSizeData.count == 8 else { break }
                    atomSize = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                    headerSize = 16
                } else if size == 0 {
                    // Size 0 means atom extends to end of file
                    atomSize = endOffset - currentOffset
                } else {
                    atomSize = UInt64(size)
                }
                
                // Check if this is the atom we're looking for
                if type == targetFourCC {
                    let contentStart = currentOffset + headerSize
                    let contentEnd = min(currentOffset + atomSize, endOffset)
                    return contentStart..<contentEnd
                }
                
                // Move to next atom
                currentOffset += atomSize
                
                // Safety check for invalid atom sizes
                if atomSize == 0 { break }
                
            } catch {
                break
            }
        }
        
        return nil
    }
    
    /// Find the video track within moov atom
    private static func findVideoTrack(in fileHandle: FileHandle, moovRange: Range<UInt64>) -> Range<UInt64>? {
        // We need to iterate through trak atoms and find the one with vmhd (video media handler)
        var searchOffset = moovRange.lowerBound
        
        while searchOffset < moovRange.upperBound {
            do {
                try fileHandle.seek(toOffset: searchOffset)
                
                guard let headerData = try fileHandle.read(upToCount: 8),
                      headerData.count == 8 else { break }
                
                let size = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let typeData = headerData.subdata(in: 4..<8)
                let type = String(data: typeData, encoding: .ascii) ?? ""
                
                var atomSize: UInt64
                var headerSize: UInt64 = 8
                
                if size == 1 {
                    guard let extSizeData = try fileHandle.read(upToCount: 8),
                          extSizeData.count == 8 else { break }
                    atomSize = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                    headerSize = 16
                } else if size == 0 {
                    atomSize = moovRange.upperBound - searchOffset
                } else {
                    atomSize = UInt64(size)
                }
                
                if type == "trak" {
                    let trakContentStart = searchOffset + headerSize
                    let trakContentEnd = searchOffset + atomSize
                    let trakRange = trakContentStart..<trakContentEnd
                    
                    // Check if this is a video track by looking for vmhd in minf
                    if let mdiaRange = findAtom(fourCC: "mdia", in: fileHandle, searchRange: trakRange),
                       let minfRange = findAtom(fourCC: "minf", in: fileHandle, searchRange: mdiaRange),
                       findAtom(fourCC: "vmhd", in: fileHandle, searchRange: minfRange) != nil {
                        return trakRange
                    }
                }
                
                // Move to next atom
                searchOffset += atomSize
                if atomSize == 0 { break }
                
            } catch {
                break
            }
        }
        
        return nil
    }
    
    /// Parse mdhd atom to get timescale
    private static func parseMediaHeaderTimescale(in fileHandle: FileHandle, mdiaRange: Range<UInt64>) -> UInt32? {
        guard let mdhdRange = findAtom(fourCC: "mdhd", in: fileHandle, searchRange: mdiaRange) else {
            return nil
        }
        
        do {
            try fileHandle.seek(toOffset: mdhdRange.lowerBound)
            
            // Version (1 byte) + flags (3 bytes)
            guard let versionFlags = try fileHandle.read(upToCount: 4),
                  versionFlags.count == 4 else { return nil }
            
            let version = versionFlags[0]
            
            if version == 0 {
                // Version 0: 32-bit times
                // Skip creation_time (4) + modification_time (4)
                _ = try fileHandle.read(upToCount: 8)
                
                // Timescale (4 bytes)
                guard let timescaleData = try fileHandle.read(upToCount: 4),
                      timescaleData.count == 4 else { return nil }
                
                return timescaleData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            } else {
                // Version 1: 64-bit times
                // Skip creation_time (8) + modification_time (8)
                _ = try fileHandle.read(upToCount: 16)
                
                // Timescale (4 bytes)
                guard let timescaleData = try fileHandle.read(upToCount: 4),
                      timescaleData.count == 4 else { return nil }
                
                return timescaleData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            }
        } catch {
            return nil
        }
    }
    
    /// Parse stss (sync sample) atom
    private static func parseStssAtom(in fileHandle: FileHandle, stblRange: Range<UInt64>) -> [UInt32]? {
        guard let stssRange = findAtom(fourCC: "stss", in: fileHandle, searchRange: stblRange) else {
            // No stss atom - this is valid for all-intra codecs
            return nil
        }
        
        do {
            try fileHandle.seek(toOffset: stssRange.lowerBound)
            
            // Version (1 byte) + flags (3 bytes)
            guard let versionFlags = try fileHandle.read(upToCount: 4),
                  versionFlags.count == 4 else { return nil }
            
            // Entry count (4 bytes)
            guard let countData = try fileHandle.read(upToCount: 4),
                  countData.count == 4 else { return nil }
            
            let entryCount = countData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Sanity check - don't try to allocate unreasonable amounts
            guard entryCount < 10_000_000 else { return nil }
            
            // Read all sync sample indices
            var indices: [UInt32] = []
            indices.reserveCapacity(Int(entryCount))
            
            // Read in chunks for efficiency
            let chunkSize = min(Int(entryCount), 10000) * 4
            var remaining = Int(entryCount)
            
            while remaining > 0 {
                let toRead = min(remaining, 10000) * 4
                guard let data = try fileHandle.read(upToCount: toRead),
                      data.count == toRead else { break }
                
                data.withUnsafeBytes { buffer in
                    let uint32Buffer = buffer.bindMemory(to: UInt32.self)
                    for i in 0..<(toRead / 4) {
                        indices.append(uint32Buffer[i].bigEndian)
                    }
                }
                
                remaining -= toRead / 4
            }
            
            return indices
        } catch {
            return nil
        }
    }
    
    /// Parse stts (time-to-sample) atom
    private static func parseSttsAtom(
        in fileHandle: FileHandle,
        stblRange: Range<UInt64>
    ) -> [(sampleCount: UInt32, sampleDuration: UInt32)]? {
        guard let sttsRange = findAtom(fourCC: "stts", in: fileHandle, searchRange: stblRange) else {
            return nil
        }
        
        do {
            try fileHandle.seek(toOffset: sttsRange.lowerBound)
            
            // Version (1 byte) + flags (3 bytes)
            guard let versionFlags = try fileHandle.read(upToCount: 4),
                  versionFlags.count == 4 else { return nil }
            
            // Entry count (4 bytes)
            guard let countData = try fileHandle.read(upToCount: 4),
                  countData.count == 4 else { return nil }
            
            let entryCount = countData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // Sanity check
            guard entryCount < 1_000_000 else { return nil }
            
            // Read all entries (8 bytes each: 4 for count, 4 for duration)
            let dataSize = Int(entryCount) * 8
            guard let data = try fileHandle.read(upToCount: dataSize),
                  data.count == dataSize else { return nil }
            
            var entries: [(sampleCount: UInt32, sampleDuration: UInt32)] = []
            entries.reserveCapacity(Int(entryCount))
            
            data.withUnsafeBytes { buffer in
                for i in 0..<Int(entryCount) {
                    let offset = i * 8
                    let sampleCount = buffer.load(fromByteOffset: offset, as: UInt32.self).bigEndian
                    let sampleDuration = buffer.load(fromByteOffset: offset + 4, as: UInt32.self).bigEndian
                    entries.append((sampleCount: sampleCount, sampleDuration: sampleDuration))
                }
            }
            
            return entries
        } catch {
            return nil
        }
    }
    
    /// Calculate timestamp for a given sample index using stts entries
    private static func calculateTimestamp(
        forSampleIndex targetIndex: UInt32,
        sttsEntries: [(sampleCount: UInt32, sampleDuration: UInt32)],
        timescale: Double
    ) -> Double {
        // Sample indices are 1-based
        var currentSample: UInt32 = 1
        var currentTime: UInt64 = 0
        
        for entry in sttsEntries {
            let entryEndSample = currentSample + entry.sampleCount
            
            if targetIndex < entryEndSample {
                // Target sample is within this entry
                let samplesIntoEntry = targetIndex - currentSample
                currentTime += UInt64(samplesIntoEntry) * UInt64(entry.sampleDuration)
                break
            }
            
            // Add time for all samples in this entry
            currentTime += UInt64(entry.sampleCount) * UInt64(entry.sampleDuration)
            currentSample = entryEndSample
        }
        
        return Double(currentTime) / timescale
    }
}

// MARK: - GOP Segment Generation

extension SyncSampleParser {
    
    /// Generate GOPSegments from sync sample data without scanning frames.
    /// This is much faster than scanning with AVAssetReader for standard MP4/MOV files.
    ///
    /// - Parameters:
    ///   - url: Media file URL
    ///   - totalDuration: Total video duration in seconds (from AVAsset)
    ///   - options: GOP extraction options
    /// - Returns: Array of GOPSegments, or nil if fast parsing not available
    ///
    /// Returns nil for:
    /// - Fragmented MP4 files (fMP4, CMAF)
    /// - All-intra codecs (ProRes, MJPEG, etc.)
    /// - Non-MP4/MOV formats
    /// - Parse errors
    public static func generateGOPSegments(
        from url: URL,
        totalDuration: Double,
        options: GOPOptions
    ) async -> [GOPSegment]? {
        guard let result = await parseSyncSamples(from: url) else {
            return nil
        }
        
        let keyframes = keyframeTimestamps(from: result)
        
        // If empty, parsing failed or all-intra codec
        guard !keyframes.isEmpty else {
            return nil
        }
        
        var segments: [GOPSegment] = []
        segments.reserveCapacity(keyframes.count)
        
        let timeRange = options.timeRange
        let maxScanSeconds = options.maxScanSeconds
        
        for i in 0..<keyframes.count {
            let startTime = keyframes[i].timestamp
            let endTime: Double
            
            if i + 1 < keyframes.count {
                endTime = keyframes[i + 1].timestamp
            } else {
                // Last GOP extends to end of video
                endTime = totalDuration
            }
            
            // Apply time range filter
            if let range = timeRange {
                if endTime < range.lowerBound { continue }
                if startTime > range.upperBound { break }
            }
            
            // Apply maxScanSeconds filter
            if let maxSeconds = maxScanSeconds, startTime > maxSeconds {
                break
            }
            
            // Calculate frame count from sample indices
            let frameCount: Int?
            if i + 1 < keyframes.count {
                let startIndex = keyframes[i].sampleIndex
                let endIndex = keyframes[i + 1].sampleIndex
                frameCount = Int(endIndex - startIndex)
            } else {
                // Last GOP - estimate from total samples
                let startIndex = keyframes[i].sampleIndex
                frameCount = Int(result.totalSampleCount - startIndex + 1)
            }
            
            let effectiveStart = max(startTime, timeRange?.lowerBound ?? startTime)
            let effectiveEnd = min(endTime, timeRange?.upperBound ?? endTime)
            
            segments.append(GOPSegment(
                startTime: effectiveStart,
                endTime: effectiveEnd,
                frameCount: frameCount,
                frames: nil  // Fast path doesn't provide frame-level detail
            ))
            
            // Check maxGOPs limit
            if let maxGOPs = options.maxGOPs, segments.count >= maxGOPs {
                break
            }
        }
        
        return segments
    }
}
