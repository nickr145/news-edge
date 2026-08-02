import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Ported 1:1 from frontend/src/styles.css `:root`. The web app is dark-only
/// (no light theme), so this app forces dark appearance too (see
/// `.preferredColorScheme(.dark)` in RootView) and uses these fixed colors
/// rather than adaptive system colors.
enum Theme {
    // MARK: Surfaces (--bg, --surface, --surface-2, --border, --border-mid)
    static let background = Color(hex: 0x040B18)
    static let surface = Color(hex: 0x080F21)       // rgba(8,15,33,0.92) flattened over --bg
    static let surface2 = Color(hex: 0x0C1630)      // rgba(12,22,48,0.8) flattened over --bg
    static let border = Color.white.opacity(0.07)
    static let borderMid = Color.white.opacity(0.13)

    // MARK: Text (--text, --muted, --dim)
    static let text = Color(hex: 0xE2E8F0)
    static let muted = Color(hex: 0x64748B)
    static let dim = Color(hex: 0x1E293B)

    // MARK: Signal colors (--accent, --blue, --warn, --danger)
    static let accent = Color(hex: 0x10D9A0)        // buy / rise / positive
    static let accentDim = Color(hex: 0x10D9A0, opacity: 0.1)
    static let info = Color(hex: 0x60A5FA)          // --blue
    static let warn = Color(hex: 0xFBBF24)          // hold / stable
    static let warnDim = Color(hex: 0xFBBF24, opacity: 0.1)
    static let danger = Color(hex: 0xF87171)        // sell / fall / negative
    static let dangerDim = Color(hex: 0xF87171, opacity: 0.12)

    // MARK: Radii (--r, --r-sm, --r-xs)
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8
    static let radiusXSmall: CGFloat = 6

    static func signalColor(_ recommendation: String) -> Color {
        switch recommendation.lowercased() {
        case "buy", "rise": return accent
        case "sell", "fall": return danger
        case "hold", "stable": return warn
        default: return muted
        }
    }

    static func sentimentColor(_ label: String) -> Color {
        switch label.lowercased() {
        case "positive": return accent
        case "negative": return danger
        default: return muted
        }
    }
}

extension Font {
    /// JetBrains Mono is used site-wide for tickers, prices, and other
    /// tabular values. SF Mono (via `.monospaced` design) is the native iOS
    /// equivalent — same tabular-numeral effect without bundling a custom font.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Matches `.card` in styles.css: --surface background, --border hairline, --r radius.
    func card() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }

    /// Matches `.metric-cell`: --surface-2 background, --border hairline, --r-xs radius.
    func metricCell() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusXSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXSmall, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
