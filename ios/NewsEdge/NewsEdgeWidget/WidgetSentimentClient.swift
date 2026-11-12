import Foundation
import NaturalLanguage

/// Deliberately self-contained rather than sharing the app target's code: widget
/// extensions have a tight memory budget and keeping this target's file membership
/// independent avoids fragile multi-target file-sharing setup in the Xcode project.
// ponytail: scoring/relevance/EWMA below duplicate NewsEdge/Services/Analytics.swift
// (same formulas). Fold into one shared file if the synced-group membership gets sorted.
// The widget has no on-device article history, so its counts reflect only Yahoo's
// latest fetch, not the app's accrued cache.
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
    /// Prefers the app's FinBERT-scored snapshot (SentimentSnapshot.swift in the app target),
    /// if under 12h old; otherwise computes from Yahoo with NLTagger.
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
                guard seen.insert(normalize(item.title)).inserted,
                      relevance(ticker: ticker, headline: item.title, symbols: item.symbols) >= 0.35
                else { continue }
                scores.append(sentiment(item.title))
            }
            guard var acc = scores.first else { return empty }
            for s in scores.dropFirst() { acc = 0.3 * s + 0.7 * acc }
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: acc, count: scores.count)
        } catch {
            return empty
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func relevance(ticker: String, headline: String, symbols: [String]) -> Double {
        let inHeadline = headline.lowercased().contains(ticker.lowercased())
        var score = 0.0
        if symbols.map({ $0.uppercased() }).contains(ticker.uppercased()) { score += 0.45 }
        if inHeadline { score += 0.40 }
        if !symbols.isEmpty { score -= min(0.25, 0.04 * Double(max(symbols.count - 1, 0))) }
        return max(0, min(1, score))
    }

    private static func sentiment(_ text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) } ?? 0
    }
}
