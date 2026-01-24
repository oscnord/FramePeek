import SwiftUI

/// Compact exposure indicator for video player overlay
/// Shows exposure status with color-coded icon and optional level bar
struct ExposureIndicator: View {
    let status: ExposureStatus
    let luminanceAverage: Double?
    let showBar: Bool
    
    init(
        status: ExposureStatus,
        luminanceAverage: Double? = nil,
        showBar: Bool = true
    ) {
        self.status = status
        self.luminanceAverage = luminanceAverage
        self.showBar = showBar
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            // Status icon
            Image(systemName: status.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
            
            // Status text
            Text(status.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
            
            // Optional exposure bar
            if showBar, let lum = luminanceAverage {
                exposureBar(value: lum)
            }
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .underexposed:
            return .blue
        case .slightlyUnder:
            return .cyan
        case .properlyExposed:
            return .green
        case .slightlyOver:
            return .yellow
        case .overexposed:
            return .orange
        case .clipped:
            return .red
        case .highDynamicRange:
            return .purple
        }
    }
    
    private func exposureBar(value: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.2))
                
                // Gradient fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan, .green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width * CGFloat(value))
                    }
                
                // Position indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .offset(x: geometry.size.width * CGFloat(value) - 3)
            }
        }
        .frame(width: 50, height: 6)
    }
}

/// Larger exposure display with detailed information
struct ExposureDetailView: View {
    let status: ExposureStatus
    let luminance: LuminanceData?
    let isHDR: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Header with status
            HStack {
                Image(systemName: status.symbolName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                
                Text(status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                if isHDR {
                    Text("HDR")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple)
                        )
                }
            }
            
            // Luminance details if available
            if let lum = luminance {
                luminanceDetails(lum)
            }
            
            // Full-width exposure bar
            fullExposureBar
        }
        .padding(DesignSystem.Padding.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Materials.ultraThin)
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .underexposed: return .blue
        case .slightlyUnder: return .cyan
        case .properlyExposed: return .green
        case .slightlyOver: return .yellow
        case .overexposed: return .orange
        case .clipped: return .red
        case .highDynamicRange: return .purple
        }
    }
    
    @ViewBuilder
    private func luminanceDetails(_ lum: LuminanceData) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Avg")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(String(format: "%.0f%%", lum.average * 100))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Min")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(String(format: "%.0f%%", lum.min * 100))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Max")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(String(format: "%.0f%%", lum.max * 100))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("CR")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.Semantic.secondary)
                Text(formatContrastRatio(lum.contrastRatio))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
    }
    
    private var fullExposureBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background with zones
                HStack(spacing: 0) {
                    // Underexposed zone
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: geometry.size.width * 0.2)
                    
                    // Slightly under zone
                    Rectangle()
                        .fill(Color.cyan.opacity(0.2))
                        .frame(width: geometry.size.width * 0.15)
                    
                    // Proper exposure zone
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: geometry.size.width * 0.30)
                    
                    // Slightly over zone
                    Rectangle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: geometry.size.width * 0.15)
                    
                    // Overexposed zone
                    Rectangle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: geometry.size.width * 0.15)
                    
                    // Clipped zone
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: geometry.size.width * 0.05)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                
                // Current position indicator
                if let lum = luminance {
                    let position = min(1.0, max(0.0, lum.average))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: geometry.size.width * CGFloat(position) - 5)
                }
            }
        }
        .frame(height: 12)
    }
    
    private func formatContrastRatio(_ ratio: Double) -> String {
        if ratio >= 1000 {
            return String(format: "%.1fK:1", ratio / 1000)
        } else {
            return String(format: "%.0f:1", ratio)
        }
    }
}

// MARK: - Mini Exposure Badge

/// Minimal exposure indicator for tight spaces
struct ExposureBadge: View {
    let status: ExposureStatus
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(shortLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.2))
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .underexposed: return .blue
        case .slightlyUnder: return .cyan
        case .properlyExposed: return .green
        case .slightlyOver: return .yellow
        case .overexposed: return .orange
        case .clipped: return .red
        case .highDynamicRange: return .purple
        }
    }
    
    private var shortLabel: String {
        switch status {
        case .underexposed: return "-2"
        case .slightlyUnder: return "-1"
        case .properlyExposed: return "OK"
        case .slightlyOver: return "+1"
        case .overexposed: return "+2"
        case .clipped: return "CLP"
        case .highDynamicRange: return "HDR"
        }
    }
}

// MARK: - Preview

#Preview("Exposure Indicators") {
    VStack(spacing: 20) {
        ForEach(ExposureStatus.allCases, id: \.self) { status in
            HStack {
                ExposureIndicator(status: status, luminanceAverage: Double.random(in: 0...1))
                Spacer()
                ExposureBadge(status: status)
            }
        }
        
        Divider()
        
        ExposureDetailView(
            status: .properlyExposed,
            luminance: LuminanceData(
                min: 0.02,
                max: 0.95,
                average: 0.45,
                percentile98: 0.90,
                percentile02: 0.05
            ),
            isHDR: false
        )
    }
    .padding()
    .frame(width: 300)
}
