import SwiftUI

struct ServerSettingsSheet: View {
    var viewModel: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var port: Int
    @State private var enableAuth: Bool
    @State private var allowRemote: Bool

    init(viewModel: ServerViewModel) {
        self.viewModel = viewModel
        _port = State(initialValue: viewModel.configuration.port)
        _enableAuth = State(initialValue: viewModel.configuration.enableAuth)
        _allowRemote = State(initialValue: viewModel.configuration.allowRemoteConnections)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Text("Server Settings")
                .font(.headline)

            Form {
                Section {
                    TextField("Port:", value: $port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Section {
                    Toggle("Enable Authentication", isOn: $enableAuth)
                        .disabled(allowRemote)

                    Toggle("Allow Remote Connections", isOn: $allowRemote)
                        .onChange(of: allowRemote) { _, newValue in
                            if newValue {
                                enableAuth = true
                            }
                        }

                    if allowRemote {
                        Text("Warning: Enabling remote connections exposes the server to the network.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if enableAuth {
                    Section("API Key") {
                        HStack {
                            Text(viewModel.apiKey)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button("Regenerate") {
                                viewModel.regenerateAPIKey()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if viewModel.isRunning {
                Text("Changes require server restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    viewModel.updatePort(port)
                    viewModel.updateAllowRemote(allowRemote)
                    viewModel.updateEnableAuth(enableAuth)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .frame(width: 400)
    }
}
