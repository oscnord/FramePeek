import SwiftUI

struct GOPRangePickerSheet: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let onAnalyze: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text(String(localized: "Analyze GOP Range"))
                        .font(.system(size: DesignSystem.Typography.title3, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Select a time range to analyze the GOP structure")
                        .font(.system(size: DesignSystem.Typography.subheadline))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                GOPRangePicker(
                    startTime: $startTime,
                    endTime: $endTime,
                    duration: duration,
                    onAnalyze: onAnalyze
                )
            }
            .padding(DesignSystem.Padding.xl2)
            
            Divider()
            
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    onAnalyze()
                } label: {
                    Label("Analyze Range", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(DesignSystem.Padding.lg)
        }
        .frame(width: 560, height: 520)
        .background(.background)
    }
}

struct GOPRangePicker: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let onAnalyze: () -> Void
    
    @State private var startText: String = ""
    @State private var endText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Quick Presets")
                    .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DesignSystem.Spacing.sm) {
                    presetButton("First 30s", start: 0, end: min(30, duration))
                    presetButton("First 60s", start: 0, end: min(60, duration))
                    if duration > 120 {
                        presetButton("First 2min", start: 0, end: min(120, duration))
                    }
                    if duration > 60 {
                        presetButton("Middle 60s", start: max(0, duration/2 - 30), end: min(duration, duration/2 + 30))
                    }
                    if duration > 30 {
                        presetButton("Last 30s", start: max(0, duration - 30), end: duration)
                    }
                    presetButton("Entire File", start: 0, end: duration)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Custom Range")
                    .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    RangeSliderView(
                        start: $startTime,
                        end: $endTime,
                        bounds: 0...duration,
                        onChanged: { start, end in
                            startText = formatTimeInput(start)
                            endText = formatTimeInput(end)
                        }
                    )
                    .frame(height: 32)
                    
                    HStack {
                        Text(formatTimeInput(startTime))
                            .font(.system(size: DesignSystem.Typography.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTimeInput(endTime))
                            .font(.system(size: DesignSystem.Typography.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Start Time")
                            .font(.system(size: DesignSystem.Typography.caption))
                            .foregroundStyle(.secondary)
                        TextField("0:00", text: $startText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                            .onSubmit {
                                if let seconds = parseTimeInput(startText) {
                                    startTime = max(0, min(seconds, endTime - 1))
                                    startText = formatTimeInput(startTime)
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("End Time")
                            .font(.system(size: DesignSystem.Typography.caption))
                            .foregroundStyle(.secondary)
                        TextField("1:00", text: $endText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                            .onSubmit {
                                if let seconds = parseTimeInput(endText) {
                                    endTime = max(startTime + 1, min(seconds, duration))
                                    endText = formatTimeInput(endTime)
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Duration")
                            .font(.system(size: DesignSystem.Typography.caption))
                            .foregroundStyle(.secondary)
                        Text(formatDurationLabel(endTime - startTime))
                            .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignSystem.Padding.md)
                            .padding(.vertical, DesignSystem.Padding.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            startText = formatTimeInput(startTime)
            endText = formatTimeInput(endTime)
        }
        .onChange(of: startTime) { _, _ in
            startText = formatTimeInput(startTime)
        }
        .onChange(of: endTime) { _, _ in
            endText = formatTimeInput(endTime)
        }
    }
    
    @ViewBuilder
    private func presetButton(_ title: String, start: Double, end: Double) -> some View {
        Button {
            startTime = start
            endTime = end
            startText = formatTimeInput(start)
            endText = formatTimeInput(end)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private func formatTimeInput(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatDurationLabel(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds >= 3600 {
            return String(format: "%.1fh", seconds / 3600)
        } else if totalSeconds >= 60 {
            return String(format: "%.1fm", seconds / 60)
        } else {
            return String(format: "%.0fs", seconds)
        }
    }
    
    private func parseTimeInput(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            return Double(parts[0] * 60 + parts[1])
        case 3:
            return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default:
            return nil
        }
    }
}

// MARK: - Range Slider

private struct RangeSliderView: View {
    @Binding var start: Double
    @Binding var end: Double
    let bounds: ClosedRange<Double>
    var onChanged: ((Double, Double) -> Void)?
    
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingRange = false
    @State private var dragStartOffset: Double = 0
    
    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 8
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let range = bounds.upperBound - bounds.lowerBound
            
            let startX = range > 0 ? CGFloat((start - bounds.lowerBound) / range) * width : 0
            let endX = range > 0 ? CGFloat((end - bounds.lowerBound) / range) * width : width
            
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                
                // Selected range
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDraggingRange {
                                    isDraggingRange = true
                                    dragStartOffset = value.startLocation.x - startX
                                }
                                let rangeWidth = end - start
                                let newStartX = value.location.x - dragStartOffset
                                let newStart = bounds.lowerBound + Double(newStartX / width) * range
                                let clampedStart = max(bounds.lowerBound, min(bounds.upperBound - rangeWidth, newStart))
                                start = clampedStart
                                end = clampedStart + rangeWidth
                                onChanged?(start, end)
                            }
                            .onEnded { _ in
                                isDraggingRange = false
                            }
                    )
                
                // Start handle
                Circle()
                    .fill(isDraggingStart ? Color.accentColor : Color.white)
                    .frame(width: handleWidth, height: handleWidth)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
                    .offset(x: startX - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingStart = true
                                let newValue = bounds.lowerBound + Double(value.location.x / width) * range
                                start = max(bounds.lowerBound, min(end - 1, newValue))
                                onChanged?(start, end)
                            }
                            .onEnded { _ in
                                isDraggingStart = false
                            }
                    )
                
                // End handle
                Circle()
                    .fill(isDraggingEnd ? Color.accentColor : Color.white)
                    .frame(width: handleWidth, height: handleWidth)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    )
                    .offset(x: endX - handleWidth / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingEnd = true
                                let newValue = bounds.lowerBound + Double(value.location.x / width) * range
                                end = max(start + 1, min(bounds.upperBound, newValue))
                                onChanged?(start, end)
                            }
                            .onEnded { _ in
                                isDraggingEnd = false
                            }
                    )
            }
            .frame(height: geo.size.height)
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }
        
        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}
