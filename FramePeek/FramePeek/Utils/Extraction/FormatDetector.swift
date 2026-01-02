import Foundation
import AVFoundation

/// Container format types for specialized extraction strategies
enum ContainerFormat {
    case standardMP4
    case fragmentedMP4
    case cmaf
    case mpegTS
    case quicktime
    case other(String)
}

/// Detects the container format of a media file
/// Uses file extension, file structure analysis, and AVAsset metadata
func detectContainerFormat(asset: AVAsset, url: URL) async -> ContainerFormat {
    // First check file extension for quick detection
    let ext = url.pathExtension.lowercased()
    
    // MPEG-TS detection via extension
    if ext == "ts" || ext == "mts" || ext == "m2ts" {
        // Verify with file signature
        if hasTSFileSignature(url: url) {
            return .mpegTS
        }
    }
    
    // QuickTime detection
    if ext == "mov" {
        return .quicktime
    }
    
    // MP4/M4V - need to check if fragmented or CMAF
    if ext == "mp4" || ext == "m4v" {
        // Check for CMAF branding first
        if let formatProfile = parseContainerFormatProfile(url: url) {
            let profileLower = formatProfile.lowercased()
            if profileLower.contains("cmf2") || profileLower.contains("cmaf") {
                return .cmaf
            }
        }
        
        // Check for fragmented MP4 structure
        if isFragmentedMP4(url: url) {
            return .fragmentedMP4
        }
        
        return .standardMP4
    }
    
    // For other formats, return generic type
    if let formatName = detectContainerFormat(url: url) {
        return .other(formatName)
    }
    
    // Default fallback
    return .other("Unknown")
}

/// Checks if file has MPEG-TS file signature (0x47 sync byte pattern)
private func hasTSFileSignature(url: URL) -> Bool {
    guard let fileHandle = FileHandle(forReadingAtPath: url.path) else { return false }
    defer { fileHandle.closeFile() }
    
    do {
        try fileHandle.seek(toOffset: 0)
        guard let data = try? fileHandle.read(upToCount: 188) else { return false }
        
        // TS packets are 188 bytes, starting with 0x47 sync byte
        // Check first few packets
        let bytes = [UInt8](data)
        for i in stride(from: 0, to: min(bytes.count, 188 * 3), by: 188) {
            if i < bytes.count && bytes[i] == 0x47 {
                continue
            } else {
                return false
            }
        }
        return true
    } catch {
        return false
    }
}

/// Checks if MP4 file is fragmented (has multiple moof atoms)
private func isFragmentedMP4(url: URL) -> Bool {
    guard let fileHandle = FileHandle(forReadingAtPath: url.path) else { return false }
    defer { fileHandle.closeFile() }
    
    do {
        // Read first 64KB to check for moof atoms
        try fileHandle.seek(toOffset: 0)
        guard let data = try? fileHandle.read(upToCount: 65536) else { return false }
        
        let bytes = [UInt8](data)
        var moofCount = 0
        var offset: Int = 0
        
        // Search for 'moof' atoms
        while offset < bytes.count - 8 {
            // Check if we found 'moof' at this offset
            if offset + 7 < bytes.count {
                let atomType = String(bytes: [bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7]], encoding: .ascii) ?? ""
                if atomType == "moof" {
                    moofCount += 1
                    if moofCount > 1 {
                        // Multiple moof atoms = fragmented
                        return true
                    }
                }
            }
            
            // Try to skip to next atom
            if offset + 4 <= bytes.count {
                let size = (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
                if size > 0 && size < UInt32(bytes.count - offset) {
                    offset += Int(size)
                } else {
                    offset += 1
                }
            } else {
                break
            }
        }
        
        // Also check if there's no moov atom at the beginning (another indicator of fragmentation)
        // Standard MP4 has moov early, fragmented may have it later or not at all
        let hasMoovEarly = String(bytes: Array(bytes.prefix(100)), encoding: .ascii)?.contains("moov") ?? false
        
        // If we found moof but no early moov, likely fragmented
        if moofCount > 0 && !hasMoovEarly {
            return true
        }
        
        return false
    } catch {
        return false
    }
}

