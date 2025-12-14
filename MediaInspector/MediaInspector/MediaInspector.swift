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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Analysis Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sampling Mode")
                        .font(.headline)
                    
                    Picker("", selection: $viewModel.samplingMode) {
                        Text("Automatic").tag(MediaInspectorViewModel.SamplingMode.auto)
                        Text("Fixed Interval").tag(MediaInspectorViewModel.SamplingMode.interval)
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    switch viewModel.samplingMode {
                    case .auto:
                        HStack {
                            Text("Target Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                    case .interval:
                        HStack {
                            Text("Interval")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.samplingIntervalSeconds, in: 0.05...10.0, step: 0.05) {
                                Text("\(viewModel.samplingIntervalSeconds, specifier: "%.2f") s")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                        HStack {
                            Text("Max Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 500...50_000, step: 500) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }

                    case .everyFrame:
                        HStack {
                            Text("Maximum Samples")
                                .frame(width: 140, alignment: .leading)
                            Spacer()
                            Stepper(value: $viewModel.maxPointsTarget, in: 1_000...200_000, step: 1_000) {
                                Text("\(viewModel.maxPointsTarget)")
                                    .monospacedDigit()
                                    .frame(minWidth: 80, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $viewModel.preferAccuracy) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High Accuracy")
                            .font(.headline)
                        Text("More accurate bitrate measurements (may be slower)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    viewModel.cancelSamplingDialog()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Analyze") {
                    viewModel.confirmSamplingAndLoad()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 300)
    }
}

#Preview {
    MediaInspector()
        .environmentObject(MediaInspectorViewModel())
}
