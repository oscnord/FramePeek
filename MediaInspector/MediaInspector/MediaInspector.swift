//
//  MediaInspector.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-12-06.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct MediaInspector: View {
    @StateObject private var viewModel = MediaInspectorViewModel()

    var body: some View {
        HSplitView {
            BitrateChartView(viewModel: viewModel)
                .frame(minWidth: 400)

            InfoInspectorView(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: 320)
        }
        // Drag & drop anywhere in this view
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
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
            }
        }
        .sheet(isPresented: $viewModel.showSamplingDialog) {
            SamplingSheet(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 260)
        }
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
