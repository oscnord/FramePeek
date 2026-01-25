import Foundation

/// Utility for exporting time-series data to CSV format
public struct CSVExporter {
    
    /// Exports bitrate samples to CSV
    public static func exportBitrate(_ samples: [BitrateSample], fileInfo: FileInfo? = nil) -> String {
        var csv = ""
        
        // Header comments
        if let info = fileInfo {
            csv += "# FramePeek Bitrate Analysis\n"
            csv += "# File: \(info.name)\n"
        }
        
        // Column headers
        csv += "time,bitrate_kbps,duration_s\n"
        
        // Data rows
        for sample in samples {
            csv += String(format: "%.3f,%.1f,%.3f\n", sample.time, sample.bitrate / 1000.0, sample.duration)
        }
        
        return csv
    }
    
    /// Exports bitrate samples to CSV data
    public static func exportBitrateData(_ samples: [BitrateSample], fileInfo: FileInfo? = nil) -> Data {
        exportBitrate(samples, fileInfo: fileInfo).data(using: .utf8) ?? Data()
    }
    
    /// Exports waveform samples to CSV
    public static func exportWaveform(_ samples: [WaveformSample], trackIndex: Int = 0, fileInfo: FileInfo? = nil) -> String {
        var csv = ""
        
        // Header comments
        if let info = fileInfo {
            csv += "# FramePeek Audio Waveform\n"
            csv += "# File: \(info.name)\n"
            csv += "# Track: \(trackIndex)\n"
        }
        
        // Column headers
        csv += "time,amplitude,min,max\n"
        
        // Data rows
        for sample in samples {
            csv += String(format: "%.3f,%.4f,%.4f,%.4f\n", 
                         sample.time, sample.amplitude, sample.minAmplitude, sample.maxAmplitude)
        }
        
        return csv
    }
    
    /// Exports waveform samples to CSV data
    public static func exportWaveformData(_ samples: [WaveformSample], trackIndex: Int = 0, fileInfo: FileInfo? = nil) -> Data {
        exportWaveform(samples, trackIndex: trackIndex, fileInfo: fileInfo).data(using: .utf8) ?? Data()
    }
    
    /// Exports GOP segments to CSV
    public static func exportGOP(_ segments: [GOPSegment], fileInfo: FileInfo? = nil) -> String {
        var csv = ""
        
        // Header comments
        if let info = fileInfo {
            csv += "# FramePeek GOP Analysis\n"
            csv += "# File: \(info.name)\n"
        }
        
        // Column headers
        csv += "gop_index,start_time,end_time,duration,frame_count\n"
        
        // Data rows
        for (index, segment) in segments.enumerated() {
            csv += String(format: "%d,%.3f,%.3f,%.3f,%d\n",
                         index, segment.startTime, segment.endTime, segment.duration,
                         segment.frameCount ?? 0)
        }
        
        return csv
    }
    
    /// Exports GOP segments to CSV data
    public static func exportGOPData(_ segments: [GOPSegment], fileInfo: FileInfo? = nil) -> Data {
        exportGOP(segments, fileInfo: fileInfo).data(using: .utf8) ?? Data()
    }
    
    /// Exports frame info to CSV (detailed frame-by-frame data)
    public static func exportFrames(_ frames: [FrameInfo], fileInfo: FileInfo? = nil) -> String {
        var csv = ""
        
        // Header comments
        if let info = fileInfo {
            csv += "# FramePeek Frame Analysis\n"
            csv += "# File: \(info.name)\n"
        }
        
        // Column headers
        csv += "index,time,type,size_bytes\n"
        
        // Data rows
        for (index, frame) in frames.enumerated() {
            csv += String(format: "%d,%.6f,%s,%d\n",
                         index, frame.time, frame.type.rawValue,
                         frame.size ?? 0)
        }
        
        return csv
    }
    
    /// Exports frame info to CSV data
    public static func exportFramesData(_ frames: [FrameInfo], fileInfo: FileInfo? = nil) -> Data {
        exportFrames(frames, fileInfo: fileInfo).data(using: .utf8) ?? Data()
    }
    
    /// Writes CSV string to a file
    public static func write(_ csv: String, to url: URL) throws {
        guard let data = csv.data(using: .utf8) else {
            throw CSVExporterError.encodingFailed
        }
        try data.write(to: url)
    }
}

/// Error types for CSV export
public enum CSVExporterError: Error, LocalizedError {
    case encodingFailed
    case writeFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode CSV to UTF-8"
        case .writeFailed(let error):
            return "Failed to write CSV file: \(error.localizedDescription)"
        }
    }
}
