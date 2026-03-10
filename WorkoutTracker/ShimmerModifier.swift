import SwiftUI

// MARK: - Shimmer / Skeleton loading effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.1), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton card placeholder

struct SkeletonCard: View {
    var height: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radiusMd)
            .fill(Theme.surface)
            .frame(height: height)
            .shimmer()
    }
}

// MARK: - Skeleton row (narrower, for list items)

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.border)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.border)
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.border.opacity(0.6))
                    .frame(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .shimmer()
    }
}
