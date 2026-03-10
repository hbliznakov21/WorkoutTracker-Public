import UIKit

/// Centralized haptic feedback utility.
/// Replaces scattered `UIImpactFeedbackGenerator` calls throughout the app.
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Triple pulse — used when rest timer completes
    static func triplePulse() {
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.prepare()
        gen.impactOccurred(intensity: 1.0)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            gen.impactOccurred(intensity: 1.0)
            try? await Task.sleep(for: .milliseconds(120))
            gen.impactOccurred(intensity: 1.0)
        }
    }
}
