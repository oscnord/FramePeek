import SwiftUI

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String
    let example: String?
    let baseURL: String
    @Binding var copiedEndpoint: String?

    @State private var showExample = false

    private var methodColor: Color {
        switch method {
        case "GET": .blue
        case "POST": .green
        case "DELETE": .red
        case "PUT", "PATCH": .orange
        default: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                Text(method)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .frame(width: 54)
                    .padding(.vertical, DesignSystem.Padding.xs)
                    .background(methodColor)
                    .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.small))

                Text(path)
                    .font(.system(.callout, design: .monospaced))

                Spacer()

                HStack(spacing: DesignSystem.Spacing.md) {
                    Button("Copy URL", systemImage: copiedEndpoint == path ? "checkmark" : "doc.on.doc", action: copyEndpoint)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(copiedEndpoint == path ? .green : .secondary)
                        .help(String(localized: "Copy full URL"))

                    Button("Toggle example", systemImage: showExample ? "chevron.up" : "chevron.down") {
                        withAnimation { showExample.toggle() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Show example"))
                    .opacity(example != nil ? 1 : 0)
                    .disabled(example == nil)
                }
                .frame(width: 50, alignment: .trailing)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showExample, let example {
                Text(example)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(DesignSystem.Padding.md2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: DesignSystem.CornerRadius.small))
            }
        }
    }

    private func copyEndpoint() {
        let fullURL = baseURL + path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullURL, forType: .string)

        copiedEndpoint = path

        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedEndpoint == path {
                copiedEndpoint = nil
            }
        }
    }
}
