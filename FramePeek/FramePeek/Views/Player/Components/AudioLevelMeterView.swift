import SwiftUI

/// A horizontal audio level meter with gradient coloring
struct AudioLevelMeterView: View {
    let amplitude: Double  // 0.0 to 1.0
    let width: CGFloat
    let height: CGFloat
    let showDecibels: Bool

    init(
        amplitude: Double,
        width: CGFloat = 80,
        height: CGFloat = 8,
        showDecibels: Bool = true
    ) {
        self.amplitude = min(1.0, max(0.0, amplitude))
        self.width = width
        self.height = height
        self.showDecibels = showDecibels
    }

    /// Convert linear amplitude to decibels
    private var decibels: Double {
        guard amplitude > 0 else { return -60 }
        return 20 * log10(amplitude)
    }

    /// Formatted decibel string
    private var decibelString: String {
        let db = decibels
        if db <= -60 {
            return "-∞ dB"
        }
        return String(format: "%.0f dB", db)
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Level meter bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.primary.opacity(0.1))

                    // Level indicator with gradient
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * amplitude)

                    // Peak markers at -6dB and -3dB
                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: geometry.size.width * 0.5)  // -6dB at 50%
                        Rectangle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 1)
                        Spacer()
                        Rectangle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 1)
                        Spacer()
                            .frame(width: geometry.size.width * 0.1)  // -3dB at ~70%
                    }
                }
            }
            .frame(width: width, height: height)

            // Decibel readout
            if showDecibels {
                Text(decibelString)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var gradientColors: [Color] {
        if amplitude > 0.9 {
            // Clipping - red dominant
            return [.green, .yellow, .orange, .red]
        } else if amplitude > 0.7 {
            // Hot - yellow/orange
            return [.green, .yellow, .orange]
        } else {
            // Normal - green
            return [.green.opacity(0.8), .green]
        }
    }
}

/// A compact version without dB display for tight spaces
struct CompactAudioLevelMeterView: View {
    let amplitude: Double
    let width: CGFloat
    let height: CGFloat

    init(amplitude: Double, width: CGFloat = 60, height: CGFloat = 6) {
        self.amplitude = min(1.0, max(0.0, amplitude))
        self.width = width
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.primary.opacity(0.1))

                // Level indicator
                Capsule()
                    .fill(levelColor)
                    .frame(width: max(height, geometry.size.width * amplitude))
            }
        }
        .frame(width: width, height: height)
    }

    private var levelColor: Color {
        if amplitude > 0.9 {
            return .red
        } else if amplitude > 0.7 {
            return .orange
        } else if amplitude > 0.5 {
            return .yellow
        } else {
            return .green
        }
    }
}
