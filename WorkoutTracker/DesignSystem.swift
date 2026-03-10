import SwiftUI

/// Centralized design tokens. Views can adopt these incrementally.
/// Current Theme enum remains for backward compatibility.
enum DS {
    // MARK: - Colors (matching existing Theme values)
    static let bg      = Color(hex: "0f172a")   // slate-900
    static let surface = Color(hex: "1e293b")   // slate-800
    static let border  = Color(hex: "334155")   // slate-700
    static let muted   = Color(hex: "64748b")   // slate-500
    static let subtle  = Color(hex: "94a3b8")   // slate-400
    static let accent  = Color(hex: "22c55e")   // green-500

    // Semantic colors used across views
    static let danger  = Color(hex: "ef4444")   // red-500
    static let warning = Color(hex: "f59e0b")   // amber-500
    static let info    = Color(hex: "38bdf8")   // sky-400
    static let gold    = Color(hex: "fbbf24")   // amber-400
    static let text    = Color(hex: "e2e8f0")   // slate-200
    static let dimText = Color(hex: "475569")   // slate-600

    // MARK: - Spacing
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24

    // MARK: - Corner Radii
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16

    // MARK: - Fonts
    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight)
    }
    static func footnote(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight)
    }
    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 14, weight: weight)
    }
    static func title3(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 16, weight: weight)
    }
    static func title2(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 20, weight: weight)
    }
    static func title1(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 24, weight: weight)
    }
    static func largeTitle(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 32, weight: weight)
    }
}
