import SwiftUI

struct APIDocumentationView: View {
    var viewModel: ServerViewModel
    @State private var copiedEndpoint: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl2) {
                if viewModel.isRunning {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Server is running at \(viewModel.serverURL)")
                                .font(.callout)
                                .bold()
                            Text("Use the endpoints below to analyze files via the REST API.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DesignSystem.Padding.lg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.medium))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        EndpointRow(
                            method: "POST",
                            path: "/analyze/path",
                            description: "Analyze a video file by path (with optional webhook callback)",
                            example: """
                            {
                              "path": "/path/to/video.mp4",
                              "options": { "info": true, "bitrate": true },
                              "webhook": {
                                "url": "https://example.com/callback",
                                "headers": { "Authorization": "Bearer token" }
                              }
                            }
                            """,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )

                        Divider().padding(.vertical, DesignSystem.Padding.lg)

                        EndpointRow(
                            method: "GET",
                            path: "/jobs",
                            description: "List all active and recent jobs",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )

                        Divider().padding(.vertical, DesignSystem.Padding.lg)

                        EndpointRow(
                            method: "GET",
                            path: "/jobs/{id}",
                            description: "Get job status and full analysis results",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )

                        Divider().padding(.vertical, DesignSystem.Padding.lg)

                        EndpointRow(
                            method: "DELETE",
                            path: "/jobs/{id}",
                            description: "Cancel a running job",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )

                        Divider().padding(.vertical, DesignSystem.Padding.lg)

                        EndpointRow(
                            method: "GET",
                            path: "/health",
                            description: "Health check endpoint",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )

                        Divider().padding(.vertical, DesignSystem.Padding.lg)

                        EndpointRow(
                            method: "GET",
                            path: "/info",
                            description: "Server capabilities and version info",
                            example: nil,
                            baseURL: viewModel.serverURL,
                            copiedEndpoint: $copiedEndpoint
                        )
                    }
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                } label: {
                    Text("Endpoints")
                        .font(.headline)
                        .padding(.bottom, DesignSystem.Padding.xs)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Include these in the request body's `options` object:")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: DesignSystem.Spacing.md2) {
                            OptionBadge(name: "info", description: "Metadata")
                            OptionBadge(name: "bitrate", description: "Bitrate graph")
                            OptionBadge(name: "gop", description: "GOP structure")
                            OptionBadge(name: "waveform", description: "Audio waveform")
                            OptionBadge(name: "sync", description: "A/V sync")
                            OptionBadge(name: "keyframes", description: "Keyframe list")
                            OptionBadge(name: "color", description: "Color analysis")
                            OptionBadge(name: "all", description: "All analyses")
                        }
                    }
                    .padding(.horizontal, DesignSystem.Padding.lg)
                    .padding(.vertical, DesignSystem.Padding.lg3)
                } label: {
                    Text("Analysis Options")
                        .font(.headline)
                        .padding(.bottom, DesignSystem.Padding.xs)
                }
            }
            .padding(DesignSystem.Padding.lg3)
        }
    }
}
