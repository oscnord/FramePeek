import SwiftUI

struct RequestLogSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        GroupBox {
            if viewModel.requestLog.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No requests yet")
                        .foregroundStyle(.secondary)
                    if viewModel.isRunning {
                        Text("Incoming API requests will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Padding.xl2)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Time")
                            .frame(width: 70, alignment: .leading)
                        Text("Method")
                            .frame(width: 60, alignment: .leading)
                        Text("Path")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Status")
                            .frame(width: 50, alignment: .center)
                        Text("Duration")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSystem.Padding.md)
                    .padding(.vertical, DesignSystem.Padding.sm2)

                    Divider()

                    ForEach(viewModel.requestLog) { entry in
                        RequestLogRow(entry: entry)

                        if entry.id != viewModel.requestLog.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Padding.lg)
                .padding(.vertical, DesignSystem.Padding.lg3)
            }
        } label: {
            HStack {
                Text("Request Log")
                    .font(.headline)

                Spacer()

                if !viewModel.requestLog.isEmpty {
                    Button("Clear") {
                        viewModel.clearRequestLog()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, DesignSystem.Padding.xs)
        }
    }
}
