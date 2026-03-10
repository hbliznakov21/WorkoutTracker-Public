import SwiftUI
import AudioToolbox

// MARK: - Rest Timer Bar
/// Floating bottom bar that shows during rest periods between sets.
/// Displays countdown, exercise name, progress bar, and adjust/skip buttons.

struct RestTimerBar: View {
    let restSeconds: Int
    let restTotalSeconds: Int
    let restExerciseName: String
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar along the top
            GeometryReader { geo in
                let progress = restTotalSeconds > 0
                    ? CGFloat(restTotalSeconds - restSeconds) / CGFloat(restTotalSeconds)
                    : 0
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * progress, height: 3)
                    .animation(.linear(duration: 1), value: restSeconds)
            }
            .frame(height: 3)

            HStack(spacing: 10) {
                Button { onAdjust(-15) } label: {
                    Text("\u{2212}15").font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Theme.surface)
                        .foregroundColor(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .accessibilityLabel("Subtract 15 seconds from rest timer")
                VStack(spacing: 2) {
                    Text(restExerciseName).font(.caption).foregroundColor(Theme.subtle).lineLimit(1)
                    Text("REST").font(.system(size: 9, weight: .bold)).foregroundColor(Theme.subtle)
                    Text(fmtSecs(restSeconds)).font(.system(size: 26, weight: .black)).foregroundColor(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rest timer, \(restSeconds) seconds remaining for \(restExerciseName)")
                Button { onAdjust(15) } label: {
                    Text("+15").font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Theme.surface)
                        .foregroundColor(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .accessibilityLabel("Add 15 seconds to rest timer")
                Button {
                    Haptics.medium()
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.system(size: 13, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.border).foregroundColor(Color(hex: "e2e8f0"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Skip rest timer")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Theme.surface)
        .shadow(color: .black.opacity(0.3), radius: 8, y: -4)
    }

    private func fmtSecs(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
