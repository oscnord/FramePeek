import SwiftUI

struct SkeletonView: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.medium

    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DesignSystem.Materials.ultraThin)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { _ in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.1),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 200)
                    .offset(x: shimmerOffset)
                    .blur(radius: 10)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1200
                }
            }
    }
}

struct SkeletonCard: View {
    var width: CGFloat?
    var height: CGFloat = 80
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.medium

    var body: some View {
        SkeletonView(width: width, height: height, cornerRadius: cornerRadius)
    }
}

struct SkeletonText: View {
    var width: CGFloat
    var height: CGFloat = 16
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.small

    var body: some View {
        SkeletonView(width: width, height: height, cornerRadius: cornerRadius)
    }
}

struct SkeletonChart: View {
    var height: CGFloat = 200
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.large

    var body: some View {
        SkeletonView(width: nil, height: height, cornerRadius: cornerRadius)
    }
}

#Preview {
    VStack(spacing: DesignSystem.Spacing.md) {
        SkeletonText(width: 200, height: 20)
        SkeletonCard(width: 300, height: 100)
        SkeletonChart(height: 200)
    }
    .padding()
}
