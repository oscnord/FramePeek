import Foundation
import AVFoundation

/// Container format types for specialized extraction strategies
public enum ContainerFormat {
    case standardMP4
    case fragmentedMP4
    case cmaf
    case mpegTS
    case quicktime
    case other(String)
}

/// Detects the container format of a media file
/// Uses file extension, file structure analysis, and AVAsset metadata
public func detectContainerFormat(asset: AVAsset, url: URL) async -> ContainerFormat {
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
        guard let data = try? fileHandle.read(upToCount: 188 * 3), !data.isEmpty else { return false }

        // TS packets are 188 bytes, starting with 0x47 sync byte
        // Check first few packets
        let bytes = [UInt8](data)
        for i in stride(from: 0, to: bytes.count, by: 188) {
            guard bytes[i] == 0x47 else { return false }
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
        var offset = 0

        // Walk top-level atoms looking for moof. Byte-scanning payloads would
        // false-positive on 'moof' inside media data, so stop when an atom's
        // declared size runs past the window (mdat) or is malformed.
        while offset + 8 <= bytes.count {
            if bytes[offset + 4] == 0x6D, bytes[offset + 5] == 0x6F,
               bytes[offset + 6] == 0x6F, bytes[offset + 7] == 0x66 {
                return true
            }

            let size = (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
            guard size >= 8, Int(size) <= bytes.count - offset else { break }
            offset += Int(size)
        }

        return false
    } catch {
        return false
    }
}
