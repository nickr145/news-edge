import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Accent colors ported from frontend/src/styles.css. Backgrounds/text lean on
/// system colors so the app adapts to light/dark automatically; only the
/// signal colors (which carry meaning: buy/sell/hold, positive/negative) are
/// fixed brand colors, matching the web app.
enum Theme {
    static let accent = Color(hex: 0x10D9A0)   // buy / rise / positive
    static let danger = Color(hex: 0xF87171)   // sell / fall / negative
    static let warn = Color(hex: 0xFBBF24)     // hold / stable
    static let info = Color(hex: 0x60A5FA)

    static func signalColor(_ recommendation: String) -> Color {
        switch recommendation.lowercased() {
        case "buy", "rise": return accent
        case "sell", "fall": return danger
        case "hold", "stable": return warn
        default: return .secondary
        }
    }

    static func sentimentColor(_ label: String) -> Color {
        switch label.lowercased() {
        case "positive": return accent
        case "negative": return danger
        default: return .secondary
        }
    }
}

extension View {
    /// Matches the `.card` styling shared by every panel in styles.css.
    func card() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
