import SwiftUI

struct ServerTabView: View {
    @State private var viewModel = ServerViewModel()
    @State private var selectedTab: ServerSubTab = .server

    enum ServerSubTab: String, CaseIterable {
        case server = "Server"
        case apiDocs = "API Docs"
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(ServerSubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, DesignSystem.Padding.lg)
            .padding(.bottom, DesignSystem.Padding.md)

            switch selectedTab {
            case .server:
                ServerContentView(viewModel: self.viewModel)
            case .apiDocs:
                APIDocumentationView(viewModel: self.viewModel)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $viewModel.showSettings) {
            ServerSettingsSheet(viewModel: self.viewModel)
        }
        .sheet(isPresented: $viewModel.showResultSheet) {
            if let jobId = self.viewModel.selectedJobId {
                JobResultSheet(viewModel: self.viewModel, jobId: jobId)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
        } message: {
            Text(self.viewModel.errorMessage ?? "An error occurred")
        }
    }
}

#Preview {
    ServerTabView()
}
