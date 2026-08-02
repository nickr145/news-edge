import SwiftUI

/// Small, deliberately duplicated subset of the main app's Theme.swift
/// (kept out of shared file membership, see WidgetSentimentClient.swift for
/// why). The web app has no light theme, so the widget is styled to match
/// it unconditionally rather than adapting to the system's light/dark mode.
enum WidgetTheme {
    static let background = Color(red: 0x04 / 255, green: 0x0B / 255, blue: 0x18 / 255)
    static let surface = Color(red: 0x08 / 255, green: 0x0F / 255, blue: 0x21 / 255)
    static let text = Color(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255)
    static let muted = Color(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255)
    static let accent = Color(red: 0x10 / 255, green: 0xD9 / 255, blue: 0xA0 / 255)
    static let danger = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)

    static func ewmaColor(_ value: Double) -> Color {
        if value > 0.05 { return accent }
        if value < -0.05 { return danger }
        return text
    }
}
