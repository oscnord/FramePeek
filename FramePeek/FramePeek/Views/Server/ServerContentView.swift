import SwiftUI

struct ServerContentView: View {
    var viewModel: ServerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl2) {
                ServerStatusSection(viewModel: viewModel)
                RequestLogSection(viewModel: viewModel)
                ActiveJobsSection(viewModel: viewModel)
                JobHistorySection(viewModel: viewModel)
            }
            .padding(DesignSystem.Padding.lg3)
        }
    }
}
