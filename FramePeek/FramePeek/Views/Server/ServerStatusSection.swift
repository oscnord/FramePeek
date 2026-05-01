import SwiftUI

struct ServerStatusSection: View {
    var viewModel: ServerViewModel

    @State private var uptimeRefreshTrigger = false
    let uptimeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                HStack {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 12, height: 12)

                    Text(viewModel.isRunning ? "Server Running" : "Server Offline")
                        .font(.headline)

                    Spacer()

                    Button(viewModel.isRunning ? "Stop Server" : "Start Server") {
                        Task {
                            await viewModel.toggleServer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRunning ? .red : .accentColor)
                }

                Divider()

                HStack(spacing: DesignSystem.Spacing.xl2) {
                    if viewModel.isRunning {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("URL:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.serverURL)
                                .font(.system(.body, design: .monospaced))
                            Button("Copy URL", systemImage: "doc.on.doc", action: viewModel.copyServerURL)
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .help(String(localized: "Copy URL"))
                        }

                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Uptime:")
                                .foregroundStyle(.secondary)
                            let _ = uptimeRefreshTrigger
                            Text(viewModel.uptime)
                                .monospacedDigit()
                        }
                    } else {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Port:")
                                .foregroundStyle(.secondary)
                            Text("\(viewModel.configuration.port)")
                        }

                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Auth:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.configuration.requiresAuth ? "Enabled" : "Disabled")
                        }

                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Remote:")
                                .foregroundStyle(.secondary)
                            Text(viewModel.configuration.allowRemoteConnections ? "Enabled" : "Disabled")
                        }
                    }

                    Spacer()

                    Button("Settings", systemImage: "gear") {
                        viewModel.showSettings = true
                    }
                }
                .font(.callout)

                if viewModel.configuration.requiresAuth {
                    Divider()

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("API Key:")
                            .foregroundStyle(.secondary)
                        Text(String(repeating: "*", count: 8))
                            .font(.system(.body, design: .monospaced))
                        Button("Copy API Key", systemImage: "doc.on.doc", action: viewModel.copyAPIKey)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .help(String(localized: "Copy API Key"))
                    }
                    .font(.callout)
                }
            }
            .padding(.horizontal, DesignSystem.Padding.lg)
            .padding(.vertical, DesignSystem.Padding.lg3)
        } label: {
            Text("Server Status")
                .font(.headline)
                .padding(.bottom, DesignSystem.Padding.xs)
        }
        .onReceive(uptimeTimer) { _ in
            if viewModel.isRunning {
                uptimeRefreshTrigger.toggle()
            }
        }
    }
}
