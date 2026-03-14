import SwiftUI

struct ActiveJobsSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        GroupBox {
            if viewModel.activeJobs.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No active jobs")
                        .foregroundStyle(.secondary)
                    if !viewModel.isRunning {
                        Text("Start the server to accept analysis requests")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(viewModel.activeJobs) { job in
                        ActiveJobCard(job: job, onCancel: {
                            viewModel.cancelJob(job.id)
                        })
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Active Jobs")
                    .font(.headline)
                if !viewModel.activeJobs.isEmpty {
                    Text("(\(viewModel.activeJobs.count))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}
