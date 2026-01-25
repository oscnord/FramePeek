import SwiftUI
import FramePeekCore

/// A status indicator showing A/V sync status with offset display
struct SyncStatusIndicator: View {
    let status: SyncStatus
    let offsetMs: Double?
    let showLabel: Bool

    init(status: SyncStatus, offsetMs: Double? = nil, showLabel: Bool = true) {
        self.status = status
        self.offsetMs = offsetMs
        self.showLabel = showLabel
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Offset or status text
            if showLabel {
                if let offset = offsetMs {
                    Text(formatOffset(offset))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(textColor)
                } else {
                    Text(status.displayName)
                        .font(.caption)
                        .foregroundStyle(textColor)
                }
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .inSync:
            return .green
        case .minorOffset:
            return .yellow
        case .significantOffset:
            return .red
        case .durationMismatch:
            return .orange
        case .noAudio, .noVideo:
            return .gray
        case .analysisError:
            return .red.opacity(0.5)
        }
    }

    private var textColor: Color {
        switch status {
        case .inSync:
            return .primary
        case .minorOffset:
            return .yellow
        case .significantOffset, .durationMismatch:
            return .orange
        case .noAudio, .noVideo, .analysisError:
            return .secondary
        }
    }

    private func formatOffset(_ ms: Double) -> String {
        let sign = ms >= 0 ? "+" : ""
        return String(format: "%@%.0fms", sign, ms)
    }
}

/// Compact sync indicator (just the dot)
struct CompactSyncIndicator: View {
    let status: SyncStatus

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .help(status.displayName)
    }

    private var statusColor: Color {
        switch status {
        case .inSync:
            return .green
        case .minorOffset:
            return .yellow
        case .significantOffset:
            return .red
        case .durationMismatch:
            return .orange
        case .noAudio, .noVideo:
            return .gray
        case .analysisError:
            return .red.opacity(0.5)
        }
    }
}
