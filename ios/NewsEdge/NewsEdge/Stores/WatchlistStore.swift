import Foundation
import Observation
import WidgetKit

/// Ports frontend/src/hooks/useWatchlist.js — same `localStorage` key, now UserDefaults.
/// Stored in the shared App Group suite (not `.standard`) so the
/// WatchlistSentimentWidget extension, running in its own process, can read
/// the same watchlist.
@Observable
final class WatchlistStore {
    private static let storageKey = "newsedge_watchlist"
    private static let appGroupSuite = "group.nr.NewsEdge"

    private(set) var watchlist: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: WatchlistStore.appGroupSuite) ?? .standard) {
        self.defaults = defaults
        self.watchlist = (defaults.array(forKey: Self.storageKey) as? [String]) ?? []
    }

    func add(_ ticker: String) {
        guard !watchlist.contains(ticker) else { return }
        watchlist.append(ticker)
        persist()
    }

    func remove(_ ticker: String) {
        watchlist.removeAll { $0 == ticker }
        persist()
    }

    func toggle(_ ticker: String) {
        if watchlist.contains(ticker) {
            remove(ticker)
        } else {
            add(ticker)
        }
    }

    func isWatched(_ ticker: String) -> Bool {
        watchlist.contains(ticker)
    }

    private func persist() {
        defaults.set(watchlist, forKey: Self.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
