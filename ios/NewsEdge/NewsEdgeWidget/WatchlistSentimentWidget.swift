import WidgetKit
import SwiftUI

struct WatchlistEntry: TimelineEntry {
    let date: Date
    let items: [WidgetTickerSentiment]
}

struct WatchlistProvider: TimelineProvider {
    static let watchlistKey = "newsedge_watchlist"
    static let appGroupSuite = "group.nr.NewsEdge"

    func placeholder(in context: Context) -> WatchlistEntry {
        WatchlistEntry(date: .now, items: [
            WidgetTickerSentiment(ticker: "AAPL", ewmaCompound: 0.12, count: 42),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchlistEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchlistEntry>) -> Void) {
        Task {
            var items: [WidgetTickerSentiment] = []
            for ticker in watchedTickers().prefix(4) {
                items.append(await WidgetAPI.fetchSentiment(ticker: ticker))
            }
            let entry = WatchlistEntry(date: .now, items: items)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func watchedTickers() -> [String] {
        let defaults = UserDefaults(suiteName: Self.appGroupSuite) ?? .standard
        return (defaults.array(forKey: Self.watchlistKey) as? [String]) ?? []
    }
}

struct WatchlistSentimentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchlistProvider.Entry

    private var visibleItems: [WidgetTickerSentiment] {
        switch family {
        case .systemSmall: Array(entry.items.prefix(1))
        default: Array(entry.items.prefix(4))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WATCHLIST SENTIMENT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(WidgetTheme.muted)

            if visibleItems.isEmpty {
                Spacer()
                Text("Add tickers to your watchlist in NewsEdge.")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.muted)
                Spacer()
            } else {
                ForEach(visibleItems) { item in
                    HStack {
                        Text(item.ticker)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(WidgetTheme.text)
                        Spacer()
                        if let ewma = item.ewmaCompound {
                            Text(ewma, format: .number.precision(.fractionLength(3)))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(WidgetTheme.ewmaColor(ewma))
                        } else {
                            Text("—")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(WidgetTheme.muted)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(WidgetTheme.background, for: .widget)
    }
}

struct WatchlistSentimentWidget: Widget {
    let kind = "WatchlistSentimentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchlistProvider()) { entry in
            WatchlistSentimentWidgetView(entry: entry)
        }
        .configurationDisplayName("Watchlist Sentiment")
        .description("Shows 7-day EWMA sentiment for your watched tickers.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    WatchlistSentimentWidget()
} timeline: {
    WatchlistEntry(date: .now, items: [
        WidgetTickerSentiment(ticker: "AAPL", ewmaCompound: 0.183, count: 42),
        WidgetTickerSentiment(ticker: "TSLA", ewmaCompound: -0.091, count: 17),
    ])
}
