import SwiftUI
import FramePeekCore

/// Variant table and findings for a completed ladder analysis
struct StreamingLadderResults: View {
    let result: StreamingLadderAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text(result.isVOD ? "VOD" : "Live")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                Text("\(result.variants.count) variants")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            Table(result.variants) {
                TableColumn(String(localized: "Resolution")) { variant in
                    Text(resolutionText(variant))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100)

                TableColumn(String(localized: "FPS")) { variant in
                    Text(variant.frameRate.map { String(format: "%.3g", $0) } ?? "–")
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50)

                TableColumn(String(localized: "Codecs")) { variant in
                    Text(variant.codecs.joined(separator: ", "))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(variant.codecs.joined(separator: ", "))
                }
                .width(min: 120, ideal: 200)

                TableColumn(String(localized: "Declared")) { variant in
                    Text(bitrateText(Double(variant.declaredBandwidth)))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 90)

                TableColumn(String(localized: "Measured")) { variant in
                    Text(variant.measuredAverageBitrate.map(bitrateText) ?? "–")
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 90)

                TableColumn(String(localized: "Peak")) { variant in
                    peakCell(variant)
                }
                .width(min: 80, ideal: 90)

                TableColumn(String(localized: "Segments")) { variant in
                    Text(segmentsText(variant))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110)
            }
            .frame(minHeight: 120, idealHeight: CGFloat(result.variants.count * 28 + 40), maxHeight: 240)

            if !result.findings.isEmpty {
                StreamingFindingsList(findings: result.findings)
            } else {
                Label(String(localized: "All checks passed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.horizontal)
            }
        }
    }

    private func resolutionText(_ variant: StreamingVariantReport) -> String {
        guard let w = variant.resolutionWidth, let h = variant.resolutionHeight else { return "–" }
        return "\(w)×\(h)"
    }

    private func segmentsText(_ variant: StreamingVariantReport) -> String {
        guard let stats = variant.segmentStats else { return "–" }
        return "\(stats.count) × \(String(format: "%.1f", stats.averageDuration))s"
    }

    @ViewBuilder
    private func peakCell(_ variant: StreamingVariantReport) -> some View {
        if let peak = variant.measuredPeakBitrate {
            let exceeds = variant.declaredBandwidth > 0 && peak > Double(variant.declaredBandwidth) * 1.01
            Text(bitrateText(peak))
                .monospacedDigit()
                .foregroundStyle(exceeds ? .red : .primary)
                .help(exceeds
                      ? String(localized: "Exceeds declared BANDWIDTH")
                      : String(localized: "Within declared BANDWIDTH"))
        } else {
            Text("–")
        }
    }

    private func bitrateText(_ bps: Double) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.2f Mb/s", bps / 1_000_000)
        }
        return String(format: "%.0f kb/s", bps / 1_000)
    }
}

// MARK: - Findings

struct StreamingFindingsList: View {
    let findings: [StreamingFinding]

    var body: some View {
        List {
            ForEach(StreamingFindingSeverity.allCases, id: \.self) { severity in
                let group = findings.filter { $0.severity == severity }
                if !group.isEmpty {
                    Section(sectionTitle(severity)) {
                        ForEach(group) { finding in
                            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: icon(severity))
                                    .foregroundStyle(color(severity))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.message)
                                        .font(.callout)
                                    if let uri = finding.variantURI {
                                        Text(uri)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionTitle(_ severity: StreamingFindingSeverity) -> String {
        switch severity {
        case .error: return String(localized: "Errors")
        case .warning: return String(localized: "Warnings")
        case .info: return String(localized: "Info")
        }
    }

    private func icon(_ severity: StreamingFindingSeverity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: StreamingFindingSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
