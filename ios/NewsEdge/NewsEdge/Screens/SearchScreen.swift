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
                    heroLogotype
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if watchlistStore.watchlist.isEmpty {
                    ContentUnavailableView(
                        "No tickers watched",
                        systemImage: "star",
                        description: Text("Search for a ticker above and add it to your watchlist.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(watchlistStore.watchlist, id: \.self) { symbol in
                            NavigationLink(value: symbol) {
                                WatchlistRow(symbol: symbol)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                        .onDelete { indices in
                            for index in indices {
                                watchlistStore.remove(watchlistStore.watchlist[index])
                            }
                        }
                    } header: {
                        Text("Watchlist")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.muted)
                    }
                }
            } else if matches.isEmpty {
                Text("No matches")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(matches) { ticker in
                    NavigationLink(value: ticker.symbol) {
                        TickerRow(ticker: ticker)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowSeparatorTint(Theme.border)
        .searchable(text: $query, prompt: "Search ticker or company — AAPL, Amazon, NVDA…")
        .onSubmit(of: .search) {
            let destination = matches.first?.symbol
                ?? query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !destination.isEmpty else { return }
            path.append(destination)
        }
        .navigationTitle("NewsEdge")
    }

    /// Matches .hero-logotype / .hero-mark / .hero-title / .hero-sub in styles.css.
    private var heroLogotype: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 56, height: 56)
                .overlay(
                    Text("NE")
                        .font(.mono(20, weight: .semibold))
                        .foregroundStyle(Theme.background)
                )
                .shadow(color: Theme.accent.opacity(0.28), radius: 16)

            Text("Financial news intelligence — sentiment signals, risk metrics, and ML-powered recommendations.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        SearchScreen(path: .constant(NavigationPath()))
    }
    .environment(WatchlistStore())
}
