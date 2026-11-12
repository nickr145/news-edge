import Foundation

/// Accrues Yahoo news on device so history grows beyond what one fetch returns
/// (Yahoo only serves the last day or two). One JSON file per ticker; serialized
/// by the actor so the concurrent summary/trend/articles calls don't race.
actor NewsStore {
    static let shared = NewsStore()

    private let retention: TimeInterval = 90 * 86_400
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("news", isDirectory: true)
    }

    /// Fetches fresh news, merges it into the cache, and returns everything cached
    /// (newest first). Offline or rate-limited: returns the cache if there is one.
    func articles(ticker: String) async throws -> [Article] {
        var byID = Dictionary(load(ticker).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        do {
            for article in try await YahooClient.shared.news(ticker: ticker) { byID[article.id] = article }
        } catch {
            if byID.isEmpty { throw error }
        }
        let cutoff = Date().addingTimeInterval(-retention)
        let merged = byID.values.filter { $0.publishedAt >= cutoff }.sorted { $0.publishedAt > $1.publishedAt }
        save(merged, ticker: ticker)
        return merged
    }

    private func file(_ ticker: String) -> URL {
        directory.appendingPathComponent("\(ticker.uppercased()).v2.json") // v2: FinBERT scores; v1 files hold NLTagger scores
    }

    private func load(_ ticker: String) -> [Article] {
        guard let data = try? Data(contentsOf: file(ticker)) else { return [] }
        return (try? JSONCoding.makeDecoder().decode([Article].self, from: data)) ?? []
    }

    private func save(_ articles: [Article], ticker: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? encoder.encode(articles).write(to: file(ticker), options: .atomic)
    }
}
