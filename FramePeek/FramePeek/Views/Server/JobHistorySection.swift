import SwiftUI

struct JobHistorySection: View {
    var viewModel: ServerViewModel

    var body: some View {
        GroupBox {
            if viewModel.completedJobs.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No job history")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.completedJobs) { job in
                        JobHistoryRow(job: job, viewModel: viewModel)

                        if job.id != viewModel.completedJobs.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Job History")
                    .font(.headline)

                Spacer()

                if !viewModel.completedJobs.isEmpty {
                    Button("Clear") {
                        viewModel.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}
