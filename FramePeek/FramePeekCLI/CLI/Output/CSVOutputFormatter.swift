import Foundation
import FramePeekCore

/// Formats time-series analysis results as CSV
/// Note: Only bitrate and waveform data support CSV export
struct CSVOutputFormatter: OutputFormatter {
    func format(results: [FileAnalysisResult]) throws -> String {
        var lines: [String] = []
        
        // For CSV, we output time-series data
        // If multiple files, include file column
        let multiFile = results.count > 1
        
        // Determine what data we have
        let hasBitrate = results.contains { $0.result?.bitrate != nil }
        let hasWaveform = results.contains { $0.result?.waveforms != nil }
        
        if hasBitrate {
            // Bitrate CSV
            if multiFile {
                lines.append("file,time,bitrate_bps,duration")
            } else {
                lines.append("time,bitrate_bps,duration")
            }
            
            for fileResult in results {
                guard let bitrate = fileResult.result?.bitrate else { continue }
                let samples = bitrate.samples
                
                for sample in samples {
                    if multiFile {
                        lines.append("\(escapeCSV(fileResult.path)),\(sample.time),\(sample.bitrate),\(sample.duration)")
                    } else {
                        lines.append("\(sample.time),\(sample.bitrate),\(sample.duration)")
                    }
                }
            }
        } else if hasWaveform {
            // Waveform CSV
            if multiFile {
                lines.append("file,track,time,amplitude")
            } else {
                lines.append("track,time,amplitude")
            }
            
            for fileResult in results {
                guard let waveforms = fileResult.result?.waveforms else { continue }
                
                for (trackId, samples) in waveforms {
                    for sample in samples {
                        if multiFile {
                            lines.append("\(escapeCSV(fileResult.path)),\(trackId),\(sample.time),\(sample.amplitude)")
                        } else {
                            lines.append("\(trackId),\(sample.time),\(sample.amplitude)")
                        }
                    }
                }
            }
        } else {
            // Metadata CSV (basic info)
            if multiFile {
                lines.append("file,duration,resolution,codec,overall_bitrate,frame_rate")
            } else {
                lines.append("duration,resolution,codec,overall_bitrate,frame_rate")
            }
            
            for fileResult in results {
                guard let metadata = fileResult.result?.metadata else {
                    if multiFile {
                        lines.append("\(escapeCSV(fileResult.path)),,,,,")
                    }
                    continue
                }
                
                let duration = metadata.duration
                let resolution = metadata.resolution
                let codec = metadata.codec
                let bitrate = metadata.overallBitrate
                let frameRate = metadata.frameRate
                
                if multiFile {
                    lines.append("\(escapeCSV(fileResult.path)),\(duration),\(resolution),\(escapeCSV(codec)),\(escapeCSV(bitrate)),\(frameRate)")
                } else {
                    lines.append("\(duration),\(resolution),\(escapeCSV(codec)),\(escapeCSV(bitrate)),\(frameRate)")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
