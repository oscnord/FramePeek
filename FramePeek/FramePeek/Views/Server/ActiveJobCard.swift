import SwiftUI
import FramePeekCore

struct ActiveJobCard: View {
    let job: AnalysisJob
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text(job.fileName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            HStack {
                Text("Source: \(job.source.rawValue.capitalized)")
                Text("*")
                if let started = job.startedAt {
                    Text("Started: \(started, style: .relative) ago")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)

                Text("\(Int(job.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            if let phase = job.currentPhase {
                Text(phase.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(AnalysisPhase.allCases, id: \.self) { phase in
                    if let status = job.phaseStatuses[phase], status != .skipped {
                        PhaseIndicator(phase: phase, status: status)
                    }
                }
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}
