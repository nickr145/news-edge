import SwiftUI

/// Ports the per-card fetch in frontend/src/components/WatchlistPanel.jsx (7-day EWMA + article count).
struct WatchlistRow: View {
    let symbol: String
    @State private var summary: SentimentSummary?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol).font(.headline)
                Text(summary.map { "\($0.count) articles" } ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let ewma = summary?.ewmaCompound {
                Text(ewma, format: .number.precision(.fractionLength(3)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(ewmaColor(ewma))
            }
        }
        .task(id: symbol) {
            summary = try? await APIClient.shared.sentimentSummary(ticker: symbol, days: 7)
        }
    }

    private func ewmaColor(_ value: Double) -> Color {
        if value > 0.05 { return Theme.accent }
        if value < -0.05 { return Theme.danger }
        return .primary
    }
}

#Preview {
    List {
        WatchlistRow(symbol: "AAPL")
    }
}
