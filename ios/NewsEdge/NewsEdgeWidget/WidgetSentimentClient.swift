import Foundation

/// The widget compiles ../Shared (Analytics etc.) so its math matches the app's. It cannot
/// afford the Core ML model, so `Analytics.sentiment` uses NLTagger here (FinBERT is only
/// bundled in the app). It prefers the app's FinBERT-scored snapshot when one exists.
struct WidgetTickerSentiment: Identifiable {
    var id: String { ticker }
    let ticker: String
    let ewmaCompound: Double?
    let count: Int
}

private struct SearchPayload: Decodable {
    struct Item: Decodable {
        let title: String?
        let providerPublishTime: Int?
        let relatedTickers: [String]?
    }
    let news: [Item]
}

enum WidgetAPI {
    /// Prefers the app's snapshot (SentimentSnapshot.swift in the app target) if under 12h old.
    static func fetchSentiment(ticker: String, days: Int = 7) async -> WidgetTickerSentiment {
        let shared = UserDefaults(suiteName: "group.nr.NewsEdge")
        if let snap = (shared?.dictionary(forKey: "newsedge_sentiment_snapshot") as? [String: [Double]])?[ticker.uppercased()],
           snap.count == 3, Date().timeIntervalSince1970 - snap[2] < 12 * 3600 {
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: snap[0], count: Int(snap[1]))
        }
        return await fetchFromYahoo(ticker: ticker, days: days)
    }

    private static func fetchFromYahoo(ticker: String, days: Int) async -> WidgetTickerSentiment {
        let empty = WidgetTickerSentiment(ticker: ticker, ewmaCompound: nil, count: 0)
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: ticker.uppercased()),
            URLQueryItem(name: "newsCount", value: "50"),
            URLQueryItem(name: "quotesCount", value: "0"),
        ]
        guard let url = components.url else { return empty }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let items = try JSONDecoder().decode(SearchPayload.self, from: data).news
                .compactMap { item -> (title: String, time: Int, symbols: [String])? in
                    guard let title = item.title, let time = item.providerPublishTime else { return nil }
                    return (title, time, item.relatedTickers ?? [])
                }
                .sorted { $0.time > $1.time } // newest first so dedup keeps the newest

            let since = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
            var seen = Set<String>()
            var scores: [Double] = []
            for item in items.reversed() where Double(item.time) >= since { // oldest first for EWMA
                guard seen.insert(Analytics.dedupKey(item.title)).inserted,
                      Analytics.relevance(ticker: ticker, headline: item.title, symbols: item.symbols) >= 0.35
                else { continue }
                scores.append(Analytics.sentiment(item.title))
            }
            guard !scores.isEmpty else { return empty }
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: Analytics.ewma(scores), count: scores.count)
        } catch {
            return empty
        }
    }
}
