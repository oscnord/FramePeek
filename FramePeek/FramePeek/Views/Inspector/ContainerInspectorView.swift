import SwiftUI
import FramePeekCore

// MARK: - Container Inspector View

/// Displays a tree view of MP4/MOV container structure
struct ContainerInspectorView: View {
    let result: ContainerAnalysisResult

    @State private var expandedAtoms: Set<UUID> = []
    @State private var hoveredAtom: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with legend
            headerView

            Divider()
                .padding(.vertical, DesignSystem.Spacing.sm)

            // Atom tree
            ForEach(result.atoms) { atom in
                AtomRowView(
                    atom: atom,
                    depth: 0,
                    expandedAtoms: $expandedAtoms,
                    hoveredAtom: $hoveredAtom
                )
            }
        }
        .padding(.horizontal, DesignSystem.Padding.md)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Format info
            HStack(spacing: DesignSystem.Spacing.md) {
                Label(result.format.rawValue, systemImage: "doc.badge.gearshape")
                    .font(.headline)

                Text("\(result.totalAtomCount) atoms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatBytes(result.fileSize))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Legend
            legendView
        }
        .padding(.horizontal, DesignSystem.Padding.md)
        .padding(.vertical, DesignSystem.Padding.sm)
    }

    private var legendView: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            ForEach([AtomCategory.container, .videoTrack, .audioTrack, .metadata, .timing, .data], id: \.self) { category in
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.caption2)
                        .foregroundStyle(category.color)
                    Text(category.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Atom Row View

private struct AtomRowView: View {
    let atom: ContainerAtom
    let depth: Int
    @Binding var expandedAtoms: Set<UUID>
    @Binding var hoveredAtom: UUID?

    private var metadata: AtomMetadata {
        AtomRegistry.metadata(for: atom.fourCC)
    }

    private var isExpanded: Bool {
        expandedAtoms.contains(atom.id)
    }

    private var isHovered: Bool {
        hoveredAtom == atom.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row content
            HStack(spacing: 6) {
                // Indentation
                if depth > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<depth, id: \.self) { _ in
                            Color.secondary.opacity(0.2)
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 8)
                        }
                    }
                    .fixedSize()
                }

                // Expand/collapse button for containers
                if atom.isContainer {
                    Button {
                        if isExpanded {
                            expandedAtoms.remove(atom.id)
                        } else {
                            expandedAtoms.insert(atom.id)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.snappy(duration: 0.15), value: isExpanded)
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                // Category icon
                Image(systemName: metadata.category.icon)
                    .font(.caption)
                    .foregroundStyle(metadata.category.color)
                    .frame(width: 14)

                // FourCC code
                Text(atom.fourCC)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                // Human-readable name
                Text(metadata.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Size
                Text(formatSize(atom.size))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredAtom = hovering ? atom.id : nil
            }
            .help(metadata.description)

            // Children (if expanded)
            if isExpanded && atom.isContainer {
                ForEach(atom.children) { child in
                    AtomRowView(
                        atom: child,
                        depth: depth + 1,
                        expandedAtoms: $expandedAtoms,
                        hoveredAtom: $hoveredAtom
                    )
                }
            }
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleAtoms = [
        ContainerAtom(
            fourCC: "ftyp",
            size: 32,
            offset: 0,
            headerSize: 8,
            children: []
        ),
        ContainerAtom(
            fourCC: "moov",
            size: 1_200_000,
            offset: 32,
            headerSize: 8,
            children: [
                ContainerAtom(
                    fourCC: "mvhd",
                    size: 108,
                    offset: 40,
                    headerSize: 8,
                    children: []
                ),
                ContainerAtom(
                    fourCC: "trak",
                    size: 800_000,
                    offset: 148,
                    headerSize: 8,
                    children: [
                        ContainerAtom(
                            fourCC: "tkhd",
                            size: 92,
                            offset: 156,
                            headerSize: 8,
                            children: []
                        ),
                        ContainerAtom(
                            fourCC: "mdia",
                            size: 700_000,
                            offset: 248,
                            headerSize: 8,
                            children: [
                                ContainerAtom(
                                    fourCC: "mdhd",
                                    size: 32,
                                    offset: 256,
                                    headerSize: 8,
                                    children: []
                                ),
                                ContainerAtom(
                                    fourCC: "hdlr",
                                    size: 45,
                                    offset: 288,
                                    headerSize: 8,
                                    children: []
                                ),
                                ContainerAtom(
                                    fourCC: "minf",
                                    size: 600_000,
                                    offset: 333,
                                    headerSize: 8,
                                    children: [
                                        ContainerAtom(
                                            fourCC: "stbl",
                                            size: 500_000,
                                            offset: 341,
                                            headerSize: 8,
                                            children: [
                                                ContainerAtom(
                                                    fourCC: "stsd",
                                                    size: 150,
                                                    offset: 349,
                                                    headerSize: 8,
                                                    children: []
                                                ),
                                                ContainerAtom(
                                                    fourCC: "stss",
                                                    size: 1200,
                                                    offset: 499,
                                                    headerSize: 8,
                                                    children: []
                                                ),
                                                ContainerAtom(
                                                    fourCC: "stsz",
                                                    size: 400_000,
                                                    offset: 1699,
                                                    headerSize: 8,
                                                    children: []
                                                )
                                            ]
                                        )
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        ),
        ContainerAtom(
            fourCC: "mdat",
            size: 500_000_000,
            offset: 1_200_032,
            headerSize: 8,
            children: []
        )
    ]

    let result = ContainerAnalysisResult(
        atoms: sampleAtoms,
        fileSize: 501_200_032,
        format: .mp4,
        isFragmented: false
    )

    return ContainerInspectorView(result: result)
        .frame(width: 400, height: 600)
}
