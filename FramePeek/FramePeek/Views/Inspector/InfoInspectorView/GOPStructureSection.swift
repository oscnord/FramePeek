import SwiftUI
import FramePeekCore

struct GOPStructureSection: View {
    @ObservedObject var viewModel: FramePeekViewModel

    private var analysis: GOPAnalysisResult? { viewModel.gopAnalysis }

    private var domainSeconds: Double {
        if let analysis, analysis.isPreview {
            return max(0.1, analysis.scannedUntilSeconds)
        }
        if viewModel.durationSeconds.isFinite, viewModel.durationSeconds > 0 {
            return viewModel.durationSeconds
        }
        return max(0.1, analysis?.scannedUntilSeconds ?? 0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            headerRow

            if let analysis {
                if analysis.structureType.isFixed {
                    fixedGOPVisualization(analysis: analysis)
                } else {
                    variableGOPVisualization(analysis: analysis)
                }

                statsGrid(stats: analysis.stats, structureType: analysis.structureType)
            } else if viewModel.isAnalyzingGOP {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing GOP…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DesignSystem.Padding.xs)
            } else {
                Text("No GOP analysis available. Use the main view to analyze GOP structure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignSystem.Padding.xs)
            }

            actionsRow
        }
        .padding(.leading, DesignSystem.Padding.md2)
    }

    @ViewBuilder
    private func fixedGOPVisualization(analysis: GOPAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Fixed GOP Structure")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)

                if let frameCount = analysis.structureType.fixedFrameCount {
                    Text("(\(frameCount) frames)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let repGOP = analysis.representativeGOP ?? analysis.segments.first,
               let frames = repGOP.frames, !frames.isEmpty {
                enlargedGOPFrameView(frames: frames, duration: repGOP.duration)
            } else if let repGOP = analysis.representativeGOP ?? analysis.segments.first {
                simpleGOPBar(frameCount: repGOP.frameCount ?? 0, duration: repGOP.duration)
            }
        }
    }

    @ViewBuilder
    private func enlargedGOPFrameView(frames: [FrameInfo], duration: Double) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: 1) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForFrameType(frame.type))
                        .frame(height: 28)
                        .overlay(alignment: .center) {
                            Text(frame.type.rawValue)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .clipped()

            HStack(spacing: DesignSystem.Spacing.md) {
                frameLegend

                Spacer()

                if duration > 0 {
                    Text(String(format: "%.2fs", duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func simpleGOPBar(frameCount: Int, duration: Double) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForFrameType(.i))
                    .frame(width: 6, height: 28)

                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(height: 28)
                    .overlay {
                        Text("\(frameCount) frames")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if duration > 0 {
                Text(String(format: "Duration: %.2fs", duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func variableGOPVisualization(analysis: GOPAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if case .variable = analysis.structureType {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Variable GOP Structure")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                }
            }

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let domain = max(0.001, domainSeconds)

                let bg = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 6)
                context.fill(bg, with: .color(Color.secondary.opacity(0.10)))

                guard !analysis.segments.isEmpty else { return }

                for s in analysis.segments {
                    let startX = CGFloat(max(0, min(1, s.startTime / domain))) * w
                    let endX = CGFloat(max(0, min(1, s.endTime / domain))) * w
                    let width = max(1, endX - startX)

                    let rect = CGRect(x: startX, y: 4, width: width, height: h - 8)
                    let p = Path(roundedRect: rect, cornerRadius: 3)
                    context.fill(p, with: .color(Color.accentColor.opacity(0.35)))

                    var tick = Path()
                    tick.move(to: CGPoint(x: startX, y: 2))
                    tick.addLine(to: CGPoint(x: startX, y: h - 2))
                    context.stroke(tick, with: .color(Color.accentColor.opacity(0.65)), lineWidth: 1)
                }
            }
            .frame(height: 36)
        }
    }

    private var frameLegend: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            legendItem(type: .i, label: "I")
            legendItem(type: .p, label: "P")
            legendItem(type: .b, label: "B")
        }
    }

    @ViewBuilder
    private func legendItem(type: FrameType, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(colorForFrameType(type))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func colorForFrameType(_ type: FrameType) -> Color {
        switch type {
        case .i: return Color.blue
        case .p: return Color.green
        case .b: return Color.orange
        case .unknown: return Color.gray
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md) {
            Text("GOP")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let analysis {
                Text("\(analysis.stats.gopCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                if analysis.isPreview && !analysis.structureType.isFixed {
                    Text("Preview")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if analysis.scannedUntilSeconds.isFinite, analysis.scannedUntilSeconds > 0 {
                    Text(String(format: "Scanned %.1fs", analysis.scannedUntilSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var actionsRow: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            if viewModel.isAnalyzingGOP {
                Button("Cancel") {
                    viewModel.cancelGOPAnalysis()
                }
            } else if let analysis {
                if analysis.structureType.isFixed {
                    Button("Analyze full file anyway") {
                        viewModel.analyzeGOPFullFileOverride(detectFrameTypes: true)
                    }
                    .help(String(localized: "Fixed GOP detected. Analyze the entire file to see all GOPs."))
                } else if analysis.isPreview {
                    Button("Analyze full file") {
                        viewModel.analyzeGOPFullFile(detectFrameTypes: true)
                    }
                }
            }

            Spacer()

            Text("See main view for detailed analysis")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func statsGrid(stats: GOPAnalysisStats, structureType: GOPStructureType) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if structureType.isFixed {
                if let frameCount = structureType.fixedFrameCount {
                    KVRow("Frames/GOP", "\(frameCount)", monospace: true)
                }
                KVRow("GOPs analyzed", "\(stats.gopCount)", monospace: true)
            } else {
                KVRow("GOPs", "\(stats.gopCount)", monospace: true)
            }

            if let avg = stats.avgDuration {
                KVRow("Avg", String(format: "%.2f s", avg), monospace: true)
            }
            if let min = stats.minDuration, let max = stats.maxDuration {
                if !structureType.isFixed || min != max {
                    KVRow("Range", String(format: "%.2f–%.2f s", min, max), monospace: true)
                }
            }

            if !structureType.isFixed {
                if let avgFrames = stats.avgFrameCount {
                    KVRow("Frames", String(format: "%.1f avg", avgFrames), monospace: true)
                } else if stats.minFrameCount != nil || stats.maxFrameCount != nil {
                    let min = stats.minFrameCount.map(String.init) ?? "–"
                    let max = stats.maxFrameCount.map(String.init) ?? "–"
                    KVRow("Frames", "\(min)–\(max)", monospace: true)
                }
            }
        }
    }
}
