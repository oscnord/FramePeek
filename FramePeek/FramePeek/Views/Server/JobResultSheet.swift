import SwiftUI

struct JobResultSheet: View {
    var viewModel: ServerViewModel
    let jobId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg3) {
            HStack {
                Text("Analysis Result")
                    .font(.headline)

                Spacer()

                Button("Close", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let json = viewModel.getResultJSON(for: jobId) {
                ScrollView {
                    Text(json)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.medium))

                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                    }

                    Button("Save as JSON...") {
                        saveJSON(json)
                    }

                    Spacer()

                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape)
                }
            } else {
                Text("No result available")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Padding.lg3)
        .frame(width: 700, height: 500)
    }

    private func saveJSON(_ json: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "analysis_result.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
