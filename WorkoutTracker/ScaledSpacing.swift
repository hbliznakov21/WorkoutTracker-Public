import SwiftUI

/// Dynamic Type-aware spacing values.
/// Views can adopt these incrementally by adding `let spacing = ScaledSpacing()` as a property.
///
/// Usage:
/// ```
/// struct MyView: View {
///     let spacing = ScaledSpacing()
///     var body: some View {
///         VStack(spacing: spacing.md) { ... }
///             .padding(spacing.lg)
///     }
/// }
/// ```
struct ScaledSpacing {
    @ScaledMetric(relativeTo: .body) var xs: CGFloat = 4
    @ScaledMetric(relativeTo: .body) var sm: CGFloat = 8
    @ScaledMetric(relativeTo: .body) var md: CGFloat = 12
    @ScaledMetric(relativeTo: .body) var lg: CGFloat = 16
    @ScaledMetric(relativeTo: .body) var xl: CGFloat = 20
    @ScaledMetric(relativeTo: .body) var xxl: CGFloat = 24
}
