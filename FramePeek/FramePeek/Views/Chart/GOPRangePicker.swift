import SwiftUI

struct GOPRangePickerSheet: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let onAnalyze: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxl) {
                    header
                    
                    GOPRangePicker(
                        startTime: $startTime,
                        endTime: $endTime,
                        duration: duration
                    )
                }
                .padding(DesignSystem.Padding.xxl2)
            }
            
            Divider()
            
            footerButtons
                .padding(.horizontal, DesignSystem.Padding.xxl2)
                .padding(.vertical, DesignSystem.Padding.xl)
        }
        .frame(width: 700, height: 640)
    }
    
    private var header: some View {
        Text(String(localized: "Analyze GOP Range"))
            .font(.system(size: DesignSystem.Typography.title2, weight: .semibold))
            .foregroundStyle(.primary)
    }
    
    private var footerButtons: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape)
            
            Spacer()
            
            Button(action: onAnalyze) {
                Label("Analyze Range", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)
        }
    }
}

struct GOPRangePicker: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    
    @State private var startText: String = ""
    @State private var endText: String = ""
    
    var body: some View {
        customRangeCard
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
    
    private var customRangeCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
            Text("Custom Range")
                .font(.system(size: DesignSystem.Typography.headline, weight: .semibold))
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    RangeSliderView(
                        start: $startTime,
                        end: $endTime,
                        bounds: 0...duration,
                        onChanged: { start, end in
                            startText = formatTimeInput(start)
                            endText = formatTimeInput(end)
                        }
                    )
                    .frame(height: 40)
                    
                    HStack {
                        Text(formatTimeInput(startTime))
                            .font(.system(size: DesignSystem.Typography.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTimeInput(endTime))
                            .font(.system(size: DesignSystem.Typography.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    HStack(spacing: DesignSystem.Spacing.xl) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Start Time")
                                .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("0:00", text: $startText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                                .onSubmit {
                                    guard let seconds = parseTimeInput(startText) else { return }
                                    startTime = max(0, min(seconds, endTime - 1))
                                    startText = formatTimeInput(startTime)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("End Time")
                                .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("1:00", text: $endText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .font(.system(size: DesignSystem.Typography.body, design: .monospaced))
                                .onSubmit {
                                    guard let seconds = parseTimeInput(endText) else { return }
                                    endTime = max(startTime + 1, min(seconds, duration))
                                    endText = formatTimeInput(endTime)
                                }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Duration")
                                .font(.system(size: DesignSystem.Typography.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(formatDurationLabel(endTime - startTime))
                                .font(.system(size: DesignSystem.Typography.title3, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(.horizontal, DesignSystem.Padding.lg)
                                .padding(.vertical, DesignSystem.Padding.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                                        .fill(.quaternary.opacity(0.5))
                                )
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Padding.xl2)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
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
                .padding(.vertical, DesignSystem.Padding.md)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
