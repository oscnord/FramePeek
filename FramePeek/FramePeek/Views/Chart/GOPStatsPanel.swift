import SwiftUI

struct GOPStatsPanel: View {
    let stats: GOPAnalysisStats
    let frameTypeStats: (iCount: Int, pCount: Int, bCount: Int, unknownCount: Int, total: Int)?
    
    private var patternInfo: (label: String, color: Color)? {
        // Need at least 3 GOPs to reliably determine pattern
        guard stats.gopCount >= 3,
              let min = stats.minDuration,
              let max = stats.maxDuration,
              let avg = stats.avgDuration,
              avg > 0 else {
            return nil
        }
        
        let variance = (max - min) / avg
        if variance < 0.1 {
            return ("Fixed", .green)
        } else if variance < 0.5 {
            return ("Variable", .orange)
        } else {
            return ("Irregular", .red)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Summary cards
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                summaryCard(
                    title: "Total GOPs",
                    value: "\(stats.gopCount)",
                    icon: "rectangle.split.3x1",
                    color: .blue
                )
                
                if let pattern = patternInfo {
                    summaryCard(
                        title: "Pattern",
                        value: pattern.label,
                        icon: "waveform.path",
                        color: pattern.color
                    )
                }
                
                if let avg = stats.avgDuration {
                    summaryCard(
                        title: "Avg Duration",
                        value: String(format: "%.2fs", avg),
                        icon: "clock",
                        color: .orange
                    )
                }
                
                if let frameStats = frameTypeStats, frameStats.total > 0 {
                    summaryCard(
                        title: "Frames",
                        value: "\(frameStats.total)",
                        icon: "photo.stack",
                        color: .purple
                    )
                }
            }
            
            // Frame distribution (if available)
            if let frameStats = frameTypeStats, frameStats.total > 0 {
                frameDistributionView(stats: frameStats)
                    .padding(.top, DesignSystem.Padding.xs)
            }
        }
    }
    
    @ViewBuilder
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Padding.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }
    
    @ViewBuilder
    private func frameDistributionView(stats: (iCount: Int, pCount: Int, bCount: Int, unknownCount: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Frame Distribution")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Visual bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if stats.iCount > 0 {
                        Rectangle()
                            .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(stats.iCount) / CGFloat(stats.total))
                    }
                    if stats.pCount > 0 {
                        Rectangle()
                            .fill(Color(red: 1.0, green: 0.58, blue: 0.0).opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(stats.pCount) / CGFloat(stats.total))
                    }
                    if stats.bCount > 0 {
                        Rectangle()
                            .fill(Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(stats.bCount) / CGFloat(stats.total))
                    }
                    if stats.unknownCount > 0 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(stats.unknownCount) / CGFloat(stats.total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 16)
            
            // Legend
            HStack(spacing: DesignSystem.Spacing.lg) {
                frameTypeLegend(type: .i, count: stats.iCount, total: stats.total)
                frameTypeLegend(type: .p, count: stats.pCount, total: stats.total)
                frameTypeLegend(type: .b, count: stats.bCount, total: stats.total)
                if stats.unknownCount > 0 {
                    frameTypeLegend(type: .unknown, count: stats.unknownCount, total: stats.total)
                }
                Spacer()
            }
        }
        .padding(DesignSystem.Padding.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }
    
    private func frameTypeLegend(type: FrameType, count: Int, total: Int) -> some View {
        let color: Color = {
            switch type {
            case .i:
                return Color(red: 0.0, green: 0.48, blue: 1.0)
            case .p:
                return Color(red: 1.0, green: 0.58, blue: 0.0)
            case .b:
                return Color(red: 1.0, green: 0.23, blue: 0.19)
            case .unknown:
                return .gray
            }
        }()
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(type.rawValue)
                .font(.caption)
                .fontWeight(.medium)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("(\(String(format: "%.0f%%", Double(count) / Double(total) * 100)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

