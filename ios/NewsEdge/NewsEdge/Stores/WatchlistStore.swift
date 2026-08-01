import Foundation
import Observation

/// Ports frontend/src/hooks/useWatchlist.js — same `localStorage` key, now UserDefaults.
@Observable
final class WatchlistStore {
    private static let storageKey = "newsedge_watchlist"

    private(set) var watchlist: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
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
    }
}
