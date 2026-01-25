import Foundation
import FramePeekCore

/// Formats analysis results as human-readable text
struct TextOutputFormatter: OutputFormatter {
    func format(results: [FileAnalysisResult]) throws -> String {
        var lines: [String] = []
        
        for (index, fileResult) in results.enumerated() {
            if index > 0 {
                lines.append("")
                lines.append(String(repeating: "=", count: 80))
                lines.append("")
            }
            
            lines.append("File: \(fileResult.path)")
            lines.append(String(repeating: "-", count: 80))
            
            if let error = fileResult.error {
                lines.append("ERROR: \(error)")
                continue
            }
            
            guard let result = fileResult.result else {
                lines.append("No results available")
                continue
            }
            
            // Metadata
            if let metadata = result.metadata {
                lines.append("")
                lines.append("METADATA")
                lines.append("  File: \(metadata.fileName)")
                lines.append("  Size: \(metadata.fileSize)")
                lines.append("  Duration: \(metadata.durationFormatted)")
                lines.append("  Resolution: \(metadata.resolution)")
                lines.append("  Frame Rate: \(metadata.frameRate)")
                lines.append("  Codec: \(metadata.codec)")
                lines.append("  Bitrate: \(metadata.overallBitrate)")
                
                if let hdrFormat = metadata.hdrFormat {
                    lines.append("  HDR: \(hdrFormat)")
                }
                
                if !metadata.audioTracks.isEmpty {
                    lines.append("  Audio Tracks: \(metadata.audioTracks.count)")
                    for (i, track) in metadata.audioTracks.enumerated() {
                        lines.append("    Track \(i + 1): \(track.codec ?? "Unknown") - \(track.channelLayout ?? "Unknown")")
                    }
                }
            }
            
            // Bitrate
            if let bitrate = result.bitrate {
                lines.append("")
                lines.append("BITRATE ANALYSIS (\(bitrate.mode) mode)")
                lines.append("  Average: \(formatBitrate(bitrate.stats.average))")
                lines.append("  Min: \(formatBitrate(bitrate.stats.min))")
                lines.append("  Max: \(formatBitrate(bitrate.stats.max))")
                if let stdDev = bitrate.stats.stdDev {
                    lines.append("  Std Dev: \(formatBitrate(stdDev))")
                }
                lines.append("  Samples: \(bitrate.samples.count)")
            }
            
            // GOP
            if let gop = result.gop {
                lines.append("")
                lines.append("GOP ANALYSIS")
                lines.append("  Structure: \(gop.structureType)")
                if let fixedCount = gop.fixedFrameCount {
                    lines.append("  Fixed Frame Count: \(fixedCount)")
                }
                lines.append("  Total GOPs: \(gop.stats.count)")
                if let avg = gop.stats.avgFrameCount {
                    lines.append("  Avg Frame Count: \(String(format: "%.1f", avg))")
                }
                if let min = gop.stats.minFrameCount, let max = gop.stats.maxFrameCount {
                    lines.append("  Frame Count Range: \(min) - \(max)")
                }
                if let avgDur = gop.stats.avgDuration {
                    lines.append("  Avg Duration: \(String(format: "%.3f", avgDur))s")
                }
            }
            
            // Waveforms
            if let waveforms = result.waveforms, !waveforms.isEmpty {
                lines.append("")
                lines.append("AUDIO WAVEFORMS")
                for (trackId, samples) in waveforms {
                    lines.append("  Track \(trackId): \(samples.count) samples")
                }
            }
            
            // Sync
            if let sync = result.sync {
                lines.append("")
                lines.append("A/V SYNC ANALYSIS")
                lines.append("  Overall Status: \(sync.overallStatus)")
                lines.append("  Video First PTS: \(String(format: "%.3f", sync.video.firstPTS))s")
                lines.append("  Video Duration: \(String(format: "%.3f", sync.video.duration))s")
                lines.append("  Variable Frame Rate: \(sync.video.isVariableFrameRate ? "Yes" : "No")")
                
                for track in sync.audio {
                    lines.append("  Audio Track \(track.trackIndex):")
                    lines.append("    Offset: \(String(format: "%.1f", track.syncOffsetMs))ms")
                    lines.append("    Status: \(track.status)")
                }
            }
            
            // Keyframes
            if let keyframes = result.keyframes, !keyframes.isEmpty {
                lines.append("")
                lines.append("KEYFRAMES")
                lines.append("  Total: \(keyframes.count)")
                if keyframes.count <= 20 {
                    for kf in keyframes {
                        lines.append("    \(String(format: "%8.3f", kf.time))s")
                    }
                } else {
                    // Show first 5, last 5
                    for kf in keyframes.prefix(5) {
                        lines.append("    \(String(format: "%8.3f", kf.time))s")
                    }
                    lines.append("    ... (\(keyframes.count - 10) more)")
                    for kf in keyframes.suffix(5) {
                        lines.append("    \(String(format: "%8.3f", kf.time))s")
                    }
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatBitrate(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.2f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.1f Kbps", bps / 1_000)
        } else {
            return String(format: "%.0f bps", bps)
        }
    }
}
