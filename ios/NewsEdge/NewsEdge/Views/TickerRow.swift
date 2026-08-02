import SwiftUI

/// Matches .ticker-dropdown-item / .ticker-dropdown-symbol / .ticker-dropdown-name.
struct TickerRow: View {
    let ticker: TickerInfo

    var body: some View {
        HStack(spacing: 14) {
            Text(ticker.symbol)
                .font(.mono(13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 56, alignment: .leading)
            Text(ticker.name)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}

#Preview {
    List {
        TickerRow(ticker: TickerInfo(symbol: "AAPL", name: "Apple Inc."))
    }
    .scrollContentBackground(.hidden)
    .background(Theme.background)
}
