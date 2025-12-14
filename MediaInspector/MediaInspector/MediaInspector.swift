//
//  MediaInspector.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
import UniformTypeIdentifiers

struct MediaInspector: View {
    @EnvironmentObject var appViewModel: MediaInspectorViewModel
    @StateObject private var viewModel = MediaInspectorViewModel()

    @AppStorage("showInspector") private var showInspector: Bool = false
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 380

    private let inspectorMin: Double = 280
    private let inspectorMax: Double = 520

    var body: some View {
        HStack(spacing: 0) {
            BitrateChartView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop(providers:))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            viewModel.pickFile()
                        } label: {
                            Label("Open…", systemImage: "folder")
                        }
                        .keyboardShortcut("o", modifiers: [.command])

                        if viewModel.isAnalyzing {
                            ProgressView().controlSize(.small)
                            Button {
                                viewModel.cancelAnalysis()
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle.fill")
                            }
                        }

                        Divider()

                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                showInspector.toggle()
                            }
                        } label: {
                            Label(showInspector ? "Hide Inspector" : "Show Inspector",
                                  systemImage: "sidebar.right")
                        }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                    }
                }

            // Right inspector that *takes space* (does not overlay)
            if showInspector {
                Rectangle()
                    .fill(.separator.opacity(0.6))
                    .frame(width: 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

                InspectorColumn(
                    width: CGFloat(inspectorWidth),
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            showInspector = false
                        }
                    }
                ) {
                    InfoInspectorView(viewModel: viewModel)
                }
                .frame(width: CGFloat(inspectorWidth))
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .trailing)),
                        removal: .move(edge: .trailing)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.98, anchor: .trailing))
                    )
                )
                .overlay(alignment: .leading) {
                    // Optional: resize handle (feels like pro apps)
                    ResizeHandle(
                        minWidth: inspectorMin,
                        maxWidth: inspectorMax,
                        width: $inspectorWidth
                    )
                    .offset(x: -4) // sits just on top of divider
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showInspector)
        .onChange(of: viewModel.extendedInfo?.fileName) {
            // Auto-show inspector when a video is loaded
            if viewModel.extendedInfo != nil && !showInspector {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showInspector = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showSamplingDialog) {
            SamplingSheet(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 300)
        }
        .sheet(isPresented: $appViewModel.showAboutView) {
            AboutView()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                viewModel.handleIncomingFile(url: url)
            }
        }
        return true
    }
}

#Preview {
    MediaInspector()
        .environmentObject(MediaInspectorViewModel())
}
