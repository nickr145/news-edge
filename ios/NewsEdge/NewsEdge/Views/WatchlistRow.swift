import SwiftUI

/// Ports the card in frontend/src/components/WatchlistPanel.jsx (7-day EWMA + article
/// count as labeled sub-cells). Removal is via the List's native swipe-to-delete
/// (see SearchScreen's `.onDelete`) rather than porting the web's visible "×" button —
/// swipe actions are the platform-native affordance for this here.
struct WatchlistRow: View {
    let symbol: String
    @State private var summary: SentimentSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(symbol)
                .font(.mono(16, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.text)

            HStack(spacing: 8) {
                metric("EWMA", ewmaText, color: ewmaColor)
                metric("Articles", summary.map { "\($0.count)" } ?? "—")
            }
        }
        .card()
        .task(id: symbol) {
            summary = try? await APIClient.shared.sentimentSummary(ticker: symbol, days: 7)
        }
    }

    private var ewmaText: String {
        summary.map { String(format: "%.3f", $0.ewmaCompound) } ?? "—"
    }

    private var ewmaColor: Color {
        guard let ewma = summary?.ewmaCompound else { return Theme.text }
        if ewma > 0.05 { return Theme.accent }
        if ewma < -0.05 { return Theme.danger }
        return Theme.text
    }

    /// Matches RiskPanelView's `metric()` — same labeled sub-cell used for Risk Metrics,
    /// reused here so the watchlist and detail screens share one visual vocabulary.
    private func metric(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.mono(14, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricCell()
    }
}

#Preview {
    List {
        WatchlistRow(symbol: "AAPL")
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Theme.background)
}
