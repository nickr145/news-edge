import Foundation

/// Mirrors frontend/src/data/tickers.js.
struct TickerInfo: Codable, Identifiable, Hashable {
    let symbol: String
    let name: String

    var id: String { symbol }
}

enum TickerCatalog {
    static let all: [TickerInfo] = {
        guard let url = Bundle.main.url(forResource: "Tickers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tickers = try? JSONDecoder().decode([TickerInfo].self, from: data)
        else {
            assertionFailure("Tickers.json missing or malformed in the app bundle")
            return []
        }
        return tickers
    }()

    /// Mirrors the ranking/filtering in frontend/src/components/TickerSearch.jsx.
    static func search(_ query: String, limit: Int = 8) -> [TickerInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)

        func matchesQuery(name: String) -> Bool {
            words.count > 1 && words.allSatisfy { name.contains($0) }
        }

        func rank(symbol: String, name: String) -> Int {
            if symbol == q { return 0 }
            if symbol.hasPrefix(q) { return 1 }
            if name.hasPrefix(q) { return 2 }
            if matchesQuery(name: name) { return 3 }
            if name.contains(q) { return 4 }
            return 5
        }

        return all
            .filter { ticker in
                let name = ticker.name.uppercased()
                return ticker.symbol.hasPrefix(q)
                    || name.hasPrefix(q)
                    || name.contains(q)
                    || matchesQuery(name: name)
            }
            .sorted { a, b in
                let rankA = rank(symbol: a.symbol, name: a.name.uppercased())
                let rankB = rank(symbol: b.symbol, name: b.name.uppercased())
                return rankA != rankB ? rankA < rankB : a.symbol < b.symbol
            }
            .prefix(limit)
            .map { $0 }
    }
}
