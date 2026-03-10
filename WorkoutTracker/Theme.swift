import SwiftUI

enum Theme {
    static let bg      = Color(hex: "0f172a")   // slate-900
    static let surface = Color(hex: "1e293b")   // slate-800
    static let border  = Color(hex: "334155")   // slate-700
    static let muted   = Color(hex: "64748b")   // slate-500
    static let subtle  = Color(hex: "94a3b8")   // slate-400
    static let accent  = Color(hex: "22c55e")   // green-500

    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16

}

// MARK: - Color hex initialiser (relocated from HomeView.swift)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Double formatting (relocated from WorkoutDetailView.swift)

extension Double {
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(self))" : String(format: "%.1f", self)
    }
}
