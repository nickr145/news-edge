import Foundation
import WidgetKit

/// Hands the app's FinBERT-scored 7-day sentiment to the widget through the App Group,
/// so the widget (which can't afford the model) shows the same numbers as the app.
/// Layout: ticker -> [ewma, count, unix time]. The widget reads the same key
/// (WidgetSentimentClient.swift) and falls back to its own NLTagger fetch when absent/stale.
enum SentimentSnapshot {
    static let key = "newsedge_sentiment_snapshot"
    private static let defaults = UserDefaults(suiteName: "group.nr.NewsEdge")

    static func publish(_ summary: SentimentSummary, now: Date = Date()) {
        guard let defaults else { return }
        var all = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        let old = all[summary.ticker]
        all[summary.ticker] = [summary.ewmaCompound, Double(summary.count), now.timeIntervalSince1970]
        defaults.set(all, forKey: key)
        if old?.prefix(2) != [summary.ewmaCompound, Double(summary.count)] {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
