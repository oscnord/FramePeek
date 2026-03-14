import SwiftUI
import FramePeekCore

struct PhaseIndicator: View {
    let phase: AnalysisPhase
    let status: JobPhaseStatus

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            statusIcon
            Text(phase.rawValue.prefix(3).uppercased())
                .font(.caption2)
        }
        .foregroundStyle(statusColor)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
        case .pending:
            Image(systemName: "circle")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        case .skipped:
            EmptyView()
        }
    }

    private var statusColor: Color {
        switch status {
        case .complete: .green
        case .processing: .blue
        case .pending: .secondary
        case .failed: .red
        case .skipped: .clear
        }
    }
}
