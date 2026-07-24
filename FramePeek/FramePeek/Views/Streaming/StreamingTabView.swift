import SwiftUI
import FramePeekCore

/// HLS ladder inspection: playlist input, variant table, findings
struct StreamingTabView: View {
    @State private var viewModel = StreamingViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            inputBar

            if viewModel.isAnalyzing {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.progressMessage ?? String(localized: "Analyzing…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            if let result = viewModel.result {
                StreamingLadderResults(result: result)
            } else if !viewModel.isAnalyzing {
                emptyState
            }

            Spacer(minLength: 0)
        }
        .padding(.top, DesignSystem.Padding.lg)
        .frame(minWidth: 600, minHeight: 400)
    }

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: DesignSystem.Spacing.sm) {
            TextField(String(localized: "HLS playlist URL (.m3u8)"), text: $viewModel.urlString)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.analyzeFromURLField() }

            if viewModel.isAnalyzing {
                Button(String(localized: "Cancel")) { viewModel.cancel() }
            } else {
                Button(String(localized: "Analyze")) { viewModel.analyzeFromURLField() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button(String(localized: "Open Folder…")) { viewModel.openLocalFolder() }
                .disabled(viewModel.isAnalyzing)
                .help(String(localized: "Analyze a local HLS folder (playlist + segments)"))
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Inspect an HLS ladder")
                .font(.title3)
            Text("Paste a playlist URL or open a local folder to check variants, declared vs measured bitrates, segment durations, and keyframe alignment.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StreamingTabView()
        .frame(width: 900, height: 600)
}
