import SwiftUI

struct TickerRow: View {
    let ticker: TickerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ticker.symbol).font(.headline)
            Text(ticker.name).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    List {
        TickerRow(ticker: TickerInfo(symbol: "AAPL", name: "Apple Inc."))
    }
}
