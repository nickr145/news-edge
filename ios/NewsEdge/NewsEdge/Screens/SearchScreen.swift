import SwiftUI

/// Ports SearchPage.jsx + TickerSearch.jsx: a searchable ticker list with a
/// watchlist section shown when there's no active query.
struct SearchScreen: View {
    @Environment(WatchlistStore.self) private var watchlistStore
    @Binding var path: NavigationPath
    @State private var query = ""

    private var matches: [TickerInfo] {
        TickerCatalog.search(query)
    }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Financial news intelligence — sentiment signals, risk metrics, and ML-powered recommendations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowSeparator(.hidden)

                if watchlistStore.watchlist.isEmpty {
                    ContentUnavailableView(
                        "No tickers watched",
                        systemImage: "star",
                        description: Text("Search for a ticker above and add it to your watchlist.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section("Watchlist") {
                        ForEach(watchlistStore.watchlist, id: \.self) { symbol in
                            NavigationLink(value: symbol) {
                                WatchlistRow(symbol: symbol)
                            }
                        }
                        .onDelete { indices in
                            for index in indices {
                                watchlistStore.remove(watchlistStore.watchlist[index])
                            }
                        }
                    }
                }
            } else if matches.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matches) { ticker in
                    NavigationLink(value: ticker.symbol) {
                        TickerRow(ticker: ticker)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search ticker or company — AAPL, Amazon, NVDA…")
        .onSubmit(of: .search) {
            let destination = matches.first?.symbol
                ?? query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !destination.isEmpty else { return }
            path.append(destination)
        }
        .navigationTitle("NewsEdge")
    }
}

#Preview {
    NavigationStack {
        SearchScreen(path: .constant(NavigationPath()))
    }
    .environment(WatchlistStore())
}
