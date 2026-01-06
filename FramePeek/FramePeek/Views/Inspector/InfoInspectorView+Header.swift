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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func actionBar(info: ExtendedVideoInfo, onClose: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Button {
                copyAll(info: info)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                    if allExpanded {
                        collapseAll()
                    } else {
                        expandAll()
                    }
                }
            } label: {
                let allExpanded = fileExpanded && videoExpanded && colorExpanded && audioExpanded && analysisExpanded
                Label(allExpanded ? "Collapse" : "Expand", 
                      systemImage: allExpanded ? "chevron.up.2" : "chevron.down.2")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer(minLength: 0)
            
            if let onClose = onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide Inspector")
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    func expandAll() {
        fileExpanded = true
        metadataExpanded = true
        videoExpanded = true
        colorExpanded = true
        audioExpanded = true
        analysisExpanded = true
    }
    
    func collapseAll() {
        fileExpanded = false
        metadataExpanded = false
        videoExpanded = false
        colorExpanded = false
        audioExpanded = false
        analysisExpanded = false
    }
}

