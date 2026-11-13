import Foundation

/// Accrues news on device so history grows beyond what one fetch returns (Yahoo only serves the
/// last day or two). One JSON file per ticker; serialized by the actor so the concurrent
/// summary/trend/articles calls don't race. The first time a ticker is seen it is also backfilled
/// from Google News RSS (~30 days).
actor NewsStore {
    static let shared = NewsStore()

    private let retention: TimeInterval = 90 * 86_400
    private let directory: URL
    nonisolated let _directoryForTests: URL
    private let yahoo: YahooClient
    private let google: GoogleNewsClient
    private let score: @Sendable (String) -> Double
    private let companyName: @Sendable (String) -> String?
    private let scorerID: @Sendable () -> String
    private let indirect: Bool
    private var indirectDone = Set<String>() // tickers whose leadership/supply/sector/macro searches already ran this session

    init(
        directory: URL? = nil,
        yahoo: YahooClient = .shared,
        google: GoogleNewsClient = GoogleNewsClient(),
        score: @escaping @Sendable (String) -> Double = { Analytics.sentiment($0) },
        companyName: @escaping @Sendable (String) -> String? = { TickerCatalog.name(for: $0) },
        scorerID: @escaping @Sendable () -> String = { FinBERTScorer.shared != nil ? "finbert" : "nltagger" },
        indirect: Bool = true
    ) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("news", isDirectory: true)
        self._directoryForTests = self.directory
        self.yahoo = yahoo
        self.google = google
        self.score = score
        self.companyName = companyName
        self.scorerID = scorerID
        self.indirect = indirect
    }

    /// Fetches fresh news, merges it into the cache, and returns everything cached
    /// (newest first). Offline or rate-limited: returns the cache if there is one.
    func articles(ticker: String) async throws -> [Article] {
        let cached = load(ticker)
        var byID = Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

        var fresh: [Article] = []
        var failure: Error?
        do { fresh += try await yahoo.news(ticker: ticker) } catch { failure = error }
        if cached.isEmpty { // first sight of this ticker: backfill history Yahoo can't give
            fresh += (try? await google.news(ticker: ticker, companyName: companyName(ticker))) ?? []
        }
        if indirect, indirectDone.insert(Analytics.yahooSymbol(ticker)).inserted {
            // News that bears on the ticker without naming it; kept only if the profile recognises how.
            let profile = NewsEvents.profile(for: ticker, companyName: companyName(ticker))
            let google = google
            let found = await withTaskGroup(of: [Article].self) { group in
                for q in NewsEvents.indirectQueries(profile) { group.addTask { (try? await google.search(query: q)) ?? [] } }
                var all: [Article] = []
                for await items in group { all += items }
                return all
            }
            fresh += found.filter { NewsEvents.exposure(profile: profile, headline: $0.headline, symbols: $0.symbols ?? []) != nil }
        }
        if let failure, byID.isEmpty, fresh.isEmpty { throw failure }

        for article in fresh where byID[article.id] == nil {
            // FinBERT costs ~70 ms/headline, so only score what the cache hasn't already.
            let compound = score(article.headline)
            var scored = article
            scored.sentimentLabel = Analytics.label(compound)
            scored.compound = compound
            byID[article.id] = scored
        }
        let cutoff = Date().addingTimeInterval(-retention)
        let merged = byID.values.filter { $0.publishedAt >= cutoff }.sorted { $0.publishedAt > $1.publishedAt }
        save(merged, ticker: ticker)
        return merged
    }

    private func file(_ ticker: String) -> URL {
        directory.appendingPathComponent("\(Analytics.yahooSymbol(ticker)).v2.\(scorerID()).json") // scores differ per scorer, so never mix them
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
