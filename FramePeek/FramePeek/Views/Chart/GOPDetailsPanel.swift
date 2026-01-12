import SwiftUI

struct GOPDetailsPanel: View {
    let segment: GOPSegment
    let index: Int
    @ObservedObject var viewModel: FramePeekViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header
            HStack {
                Text("GOP #\(index + 1)")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    viewModel.deselectGOP()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Metrics
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                metricRow(label: "Start Time", value: formatTime(segment.startTime))
                metricRow(label: "End Time", value: formatTime(segment.endTime))
                metricRow(label: "Duration", value: String(format: "%.3f s", segment.duration))
                
                if let frameCount = segment.frameCount {
                    metricRow(label: "Frame Count", value: "\(frameCount)")
                    metricRow(label: "Avg Frame Duration", value: String(format: "%.3f s", segment.duration / Double(frameCount)))
                }
            }
            
            // Frame details (if available)
            if let frames = segment.frames, !frames.isEmpty {
                Divider()
                    .padding(.vertical, DesignSystem.Padding.xs)
                
                Text("Frames")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.bottom, DesignSystem.Padding.xs)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { frameIdx, frame in
                            frameRow(frame: frame, index: frameIdx, total: frames.count)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(DesignSystem.Padding.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(DesignSystem.Materials.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: DesignSystem.Borders.thin)
                )
        )
    }
    
    @ViewBuilder
    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }
    
    @ViewBuilder
    private func frameRow(frame: FrameInfo, index: Int, total: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Frame type badge
            frameTypeBadge(type: frame.type)
            
            // Frame info
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame \(index + 1) of \(total)")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(formatTime(frame.time))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Frame size (if available)
            if let size = frame.size {
                Text(formatSize(size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DesignSystem.Padding.sm)
        .padding(.vertical, DesignSystem.Padding.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }
    
    @ViewBuilder
    private func frameTypeBadge(type: FrameType) -> some View {
        let (color, label) = frameTypeInfo(type: type)
        
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color)
            )
    }
    
    private func frameTypeInfo(type: FrameType) -> (Color, String) {
        switch type {
        case .i:
            return (Color(red: 0.0, green: 0.48, blue: 1.0), "I")
        case .p:
            return (Color(red: 1.0, green: 0.58, blue: 0.0), "P")
        case .b:
            return (Color(red: 1.0, green: 0.23, blue: 0.19), "B")
        case .unknown:
            return (.gray, "?")
        }
    }
    
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
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

