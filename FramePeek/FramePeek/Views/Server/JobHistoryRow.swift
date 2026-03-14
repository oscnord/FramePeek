import SwiftUI

struct JobHistoryRow: View {
    let job: CompletedJob
    var viewModel: ServerViewModel

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            statusIcon
                .frame(width: 20)

            Text(job.fileName)
                .lineLimit(1)

            Spacer()

            Text(job.durationFormatted)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 60, alignment: .trailing)

            Text(job.relativeTimeString)
                .foregroundStyle(.tertiary)
                .font(.callout)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: DesignSystem.Spacing.sm3) {
                if job.status == .complete {
                    Button("JSON") {
                        viewModel.viewResult(jobId: job.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Open") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: job.filePath))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if job.status == .failed {
                    Button("Error") {
                        viewModel.errorMessage = job.error ?? "Unknown error"
                        viewModel.showError = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, DesignSystem.Padding.sm2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        default:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
