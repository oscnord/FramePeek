import Foundation
import AVFoundation

// MARK: - File Size Utilities

/// Returns formatted file size string (e.g., "123.45 MiB")
public func getFileSizeString(for url: URL) -> String {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? UInt64 {
            let sizeMiB = Double(size) / 1_048_576.0 // 1024 * 1024
            return String(format: "%.2f MiB", sizeMiB)
        }
    } catch {
        print("Error getting file size: \(error.localizedDescription)")
    }
    return "Unknown"
}

/// Returns file size in bytes, or nil on error
public func getFileSizeBytes(for url: URL) -> UInt64? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? UInt64
    } catch {
        print("Error getting file size: \(error.localizedDescription)")
        return nil
    }
}

// MARK: - Bitrate Calculation

/// Calculates overall bitrate from file size and duration
public func getOverallBitrateString(asset: AVAsset, fileURL: URL) async -> String {
    let durationSec: Double
    if let loadedDuration = try? await asset.load(.duration) {
        let seconds = CMTimeGetSeconds(loadedDuration)
        if seconds.isFinite, seconds > 0 {
            durationSec = seconds
        } else {
            return "Unknown"
        }
    } else {
        return "Unknown"
    }

    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs[.size] as? UInt64 {
            let totalBits = Double(size) * 8.0
            let bitsPerSecond = totalBits / durationSec
            let kbps = bitsPerSecond / 1000.0 // kbit/s (decimal)
            return String(format: "%.0f kb/s", kbps)
        }
    } catch {
        print("Error getting overall bitrate: \(error.localizedDescription)")
    }
    return "Unknown"
}
