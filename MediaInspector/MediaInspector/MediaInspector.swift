//
//  MediaInspector.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
import UniformTypeIdentifiers

struct MediaInspector: View {
    @StateObject private var viewModel = MediaInspectorViewModel()

    @AppStorage("showInspector") private var showInspector: Bool = true
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
                            withAnimation(.snappy(duration: 0.25)) {
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

                InspectorColumn(
                    width: CGFloat(inspectorWidth),
                    onClose: {
                        withAnimation(.snappy(duration: 0.25)) {
                            showInspector = false
                        }
                    }
                ) {
                    InfoInspectorView(viewModel: viewModel)
                }
                .frame(width: CGFloat(inspectorWidth))
                .transition(.move(edge: .trailing).combined(with: .opacity))
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
        .animation(.snappy(duration: 0.25), value: showInspector)
        .sheet(isPresented: $viewModel.showSamplingDialog) {
            SamplingSheet(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 300)
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

// MARK: - Inspector Column

private struct InspectorColumn<Content: View>: View {
    let width: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Inspector")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .background(.background)
    }
}

private struct ResizeHandle: View {
    let minWidth: Double
    let maxWidth: Double
    @Binding var width: Double

    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startWidth == nil { startWidth = width }
                        let base = startWidth ?? width
                        let proposed = base - Double(value.translation.width)
                        width = min(max(proposed, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        startWidth = nil
                    }
            )
            .help("Drag to resize")
    }
}

private struct SamplingSheet: View {
    @ObservedObject var viewModel: MediaInspectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sampling strategy")
                .font(.title3)
                .fontWeight(.semibold)

            Text("For long videos, sampling every frame can create millions of points. Choose how densely to sample the timeline.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $viewModel.samplingMode) {
                Text("Auto (cap points)").tag(MediaInspectorViewModel.SamplingMode.auto)
                Text("Fixed interval").tag(MediaInspectorViewModel.SamplingMode.interval)
                Text("Every frame (heavy)").tag(MediaInspectorViewModel.SamplingMode.everyFrame)
            }
            .pickerStyle(.radioGroup)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    switch viewModel.samplingMode {
                    case .auto:
                        HStack {
                            Text("Target points")
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                            }
                        }

                        Text("Auto picks an interval based on duration to keep roughly this many points.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                    case .interval:
                        HStack {
                            Text("Interval (seconds)")
                            Spacer()
                            Stepper(value: $viewModel.samplingIntervalSeconds, in: 0.05...10.0, step: 0.05) {
                                Text("\(viewModel.samplingIntervalSeconds, specifier: "%.2f")")
                                    .monospacedDigit()
                            }
                        }

                        HStack {
                            Text("Max points")
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                            }
                        }

                        Text("Example: 1.00 s ≈ 1 point per second of video.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                    case .everyFrame:
                        HStack {
                            Text("Max points cap")
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 1_000...200_000, step: 1_000) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                            }
                        }

                        Text("Still capped for safety, but can be slow and memory-heavy.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    viewModel.cancelSamplingDialog()
                }

                Spacer()

                Button("Start") {
                    viewModel.confirmSamplingAndLoad()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 300)
    }
}

#Preview {
    MediaInspector()
}
