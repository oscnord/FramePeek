import SwiftUI
import FramePeekCore

// MARK: - Unified Tooltip Data

/// Aggregated data at a specific timestamp from all available analyses
struct UnifiedTooltipData {
    let timestamp: Double
    
    // Bitrate (if samples exist)
    var bitrate: Double?              // bits per second
    var bitratePercent: Double?       // 0.0-1.0 of peak
    
    // GOP (if gopAnalysis exists)
    var gopIndex: Int?
    var gopFrameCount: Int?
    var gopDuration: Double?
    var frameType: FrameType?         // Only if cached
    
    // Audio (if waveformData not empty, primary track only)
    var audioAmplitude: Double?       // 0.0-1.0
    
    // Keyframe (if keyframeThumbs not empty)
    var nearestKeyframeDistance: Double?  // seconds to nearest
    var isAtKeyframe: Bool = false
    
    // Color (if colorSamples not empty)
    var brightness: Double?           // 0.0-1.0
    var colorTemperature: Double?     // Kelvin
    
    /// Returns true if there's any data beyond just the timestamp
    var hasData: Bool {
        bitrate != nil ||
        gopIndex != nil ||
        audioAmplitude != nil ||
        nearestKeyframeDistance != nil ||
        brightness != nil
    }
}

// MARK: - Unified Tooltip View

/// A compact tooltip that displays aggregated data from all available analyses at a timestamp
struct UnifiedTooltip: View {
    let data: UnifiedTooltipData
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Time - always shown
            timeChip
            
            if data.hasData {
                Divider()
                    .frame(height: 16)
                    .opacity(0.5)
            }
            
            // Bitrate - if available
            if let bitrate = data.bitrate {
                bitrateChip(bitrate, percent: data.bitratePercent)
            }
            
            // GOP - if available
            if let gopIndex = data.gopIndex {
                gopChip(index: gopIndex, frameCount: data.gopFrameCount, frameType: data.frameType)
            }
            
            // Audio - if available
            if let amplitude = data.audioAmplitude {
                audioChip(amplitude)
            }
            
            // Brightness - if available
            if let brightness = data.brightness {
                brightnessChip(brightness, temperature: data.colorTemperature)
            }
            
            // Keyframe - if available
            if let distance = data.nearestKeyframeDistance {
                keyframeChip(distance: distance, isAt: data.isAtKeyframe)
            }
        }
        .font(.caption)
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.sm)
        .liquidGlassBackground(in: .rect(cornerRadius: DesignSystem.CornerRadius.large))
    }
    
    // MARK: - Time Chip
    
    private var timeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(formatTime(data.timestamp))
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Bitrate Chip
    
    @ViewBuilder
    private func bitrateChip(_ bitrate: Double, percent: Double?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.Chart.primary)
            
            Text(formatBitrate(bitrate))
                .monospacedDigit()
            
            if let percent = percent {
                Text("(\(Int(percent * 100))%)")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - GOP Chip
    
    @ViewBuilder
    private func gopChip(index: Int, frameCount: Int?, frameType: FrameType?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            
            Text("#\(index + 1)")
                .fontWeight(.medium)
            
            if let frameType = frameType {
                Text(frameType.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(colorForFrameType(frameType))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(colorForFrameType(frameType).opacity(0.2))
                    )
            }
            
            if let count = frameCount {
                Text("\(count)f")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - Audio Chip
    
    @ViewBuilder
    private func audioChip(_ amplitude: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundStyle(.green)
            
            // Mini amplitude bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(amplitude))
                }
            }
            .frame(width: 24, height: 8)
            
            Text(formatDecibels(amplitude))
                .monospacedDigit()
                .font(.caption2)
        }
    }
    
    // MARK: - Brightness Chip
    
    @ViewBuilder
    private func brightnessChip(_ brightness: Double, temperature: Double?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)
            
            Text("\(Int(brightness * 100))%")
                .monospacedDigit()
            
            if let temp = temperature {
                Text("\(Int(temp))K")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - Keyframe Chip
    
    @ViewBuilder
    private func keyframeChip(distance: Double, isAt: Bool) -> some View {
        HStack(spacing: 4) {
            if isAt {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
                Text("KF")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "diamond")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(formatKeyframeDistance(distance))
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        let ms = Int((seconds - Double(totalSeconds)) * 1000)
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        } else {
            return String(format: "%d:%02d.%03d", minutes, secs, ms)
        }
    }
    
    private func formatBitrate(_ bps: Double) -> String {
        let kbps = bps / 1000.0
        if kbps >= 1000 {
            return String(format: "%.1f Mb/s", kbps / 1000.0)
        } else {
            return String(format: "%.0f kb/s", kbps)
        }
    }
    
    private func formatDecibels(_ amplitude: Double) -> String {
        if amplitude <= 0 {
            return "-∞ dB"
        }
        let db = 20 * log10(amplitude)
        return String(format: "%.0f dB", db)
    }
    
    private func formatKeyframeDistance(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "+%.0fms", seconds * 1000)
        } else {
            return String(format: "+%.1fs", seconds)
        }
    }
    
    private func colorForFrameType(_ type: FrameType) -> Color {
        switch type {
        case .i:
            return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .p:
            return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .b:
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        case .unknown:
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Unified Tooltip - Full Data") {
    VStack {
        UnifiedTooltip(data: UnifiedTooltipData(
            timestamp: 83.456,
            bitrate: 4521000,
            bitratePercent: 0.76,
            gopIndex: 41,
            gopFrameCount: 24,
            gopDuration: 1.0,
            frameType: .i,
            audioAmplitude: 0.65,
            nearestKeyframeDistance: 0.0,
            isAtKeyframe: true,
            brightness: 0.72,
            colorTemperature: 5600
        ))
        
        UnifiedTooltip(data: UnifiedTooltipData(
            timestamp: 10.123,
            bitrate: 2500000,
            bitratePercent: 0.42,
            gopIndex: 5,
            gopFrameCount: 30,
            gopDuration: 1.0,
            frameType: .p,
            audioAmplitude: 0.3,
            nearestKeyframeDistance: 0.3,
            isAtKeyframe: false,
            brightness: nil,
            colorTemperature: nil
        ))
        
        UnifiedTooltip(data: UnifiedTooltipData(
            timestamp: 5.0,
            bitrate: 1000000,
            bitratePercent: 0.2
        ))
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
