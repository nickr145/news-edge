import SwiftUI

/// Ports SearchPage.jsx + TickerSearch.jsx: a searchable ticker list with a
/// watchlist section shown when there's no active query.
struct SearchScreen: View {
    @Environment(WatchlistStore.self) private var watchlistStore
    @Environment(FinBERTModelStore.self) private var modelStore
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

                if let banner = modelBanner {
                    banner
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

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
                            WatchlistRow(symbol: symbol)
                                .contentShape(Rectangle())
                                .onTapGesture { path.append(symbol) }
                                .accessibilityAddTraits(.isButton)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    watchlistStore.remove(symbol)
                                } label: {
                                    Label("Remove", systemImage: "xmark")
                                }
                                .tint(Theme.danger)
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

    /// Download status for the sentiment model (only while it isn't installed).
    private var modelBanner: AnyView? {
        switch modelStore.state {
        case .downloading:
            return AnyView(HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading sentiment model (105 MB, Wi-Fi). Basic sentiment until then.")
            }.font(.footnote).foregroundStyle(Theme.muted))
        case .failed(let message):
            return AnyView(HStack {
                Text("\(message) Using basic sentiment.").font(.footnote).foregroundStyle(Theme.muted)
                Spacer()
                Button("Retry") { modelStore.retry() }.font(.footnote.weight(.semibold)).tint(Theme.accent)
            })
        default:
            return nil
        }
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
    .environment(FinBERTModelStore())
}
