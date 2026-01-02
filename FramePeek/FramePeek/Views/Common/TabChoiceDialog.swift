import SwiftUI

struct TabChoiceDialog: View {
    let fileName: String
    let onChooseCurrentTab: () -> Void
    let onChooseNewTab: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("A file is already open")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text("Open \"\(fileName)\" in:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            HStack(spacing: 10) {
                Button {
                    onChooseCurrentTab()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 20))
                        Text("Current Tab")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    onChooseNewTab()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 20))
                        Text("New Tab")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(width: 360)
    }
}

#Preview {
    TabChoiceDialog(
        fileName: "example-video-file.mp4",
        onChooseCurrentTab: {},
        onChooseNewTab: {},
        onCancel: {}
    )
}

