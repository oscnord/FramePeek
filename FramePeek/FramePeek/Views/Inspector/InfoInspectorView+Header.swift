import SwiftUI

extension InfoInspectorView {
    // MARK: - Header / Actions

    func header(info: ExtendedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.fileName)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text("\(info.resolution) • \(info.codec)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignSystem.Padding.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func actionBar(info: ExtendedVideoInfo) -> some View {
        HStack(spacing: 8) {
            Button {
                copyAll(info: info)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.accessoryBar)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
