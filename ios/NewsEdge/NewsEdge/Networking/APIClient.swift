import Foundation

/// On-device replacement for the old FastAPI client: same method signatures, but
/// data comes straight from Yahoo Finance (`YahooClient`), is accrued in `NewsStore`,
/// and is scored/aggregated locally with `Analytics`. No NewsEdge backend involved.
final class APIClient {
    static let shared = APIClient()

    private let yahoo: YahooClient
    private let store: NewsStore
    private let now: @Sendable () -> Date

    init(yahoo: YahooClient = .shared, store: NewsStore = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.yahoo = yahoo
        self.store = store
        self.now = now
    }

    // MARK: - News

    func articles(
        ticker: String,
        days: Int,
        limit: Int = 100,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> [Article] {
        let all = try await relevant(ticker: ticker, since: daysAgo(Double(days)), minRelevance: minRelevance)
        return Array(all.prefix(limit))
    }

    func sentimentSummary(
        ticker: String,
        days: Int,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> SentimentSummary {
        let items = try await relevant(ticker: ticker, since: daysAgo(Double(days)), minRelevance: minRelevance)
        let weighted = items.map { ($0.compound ?? 0) * ($0.sourceWeight ?? 1) }
        var labels = ["POSITIVE": 0, "NEUTRAL": 0, "NEGATIVE": 0]
        for item in items { labels[item.sentimentLabel ?? "NEUTRAL", default: 0] += 1 }
        let summary = SentimentSummary(
            ticker: ticker.uppercased(),
            count: items.count,
            meanCompound: Analytics.mean(weighted),
            stdCompound: Analytics.std(weighted),
            ewmaCompound: signal(items, days: Double(days)),
            labelDistribution: labels
        )
        if days == 7, minRelevance == 0.35 { SentimentSnapshot.publish(summary) }
        return summary
    }

    func sentimentTrend(
        ticker: String,
        hours: Int,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> SentimentTrend {
        let items = try await relevant(ticker: ticker, since: daysAgo(Double(hours) / 24), minRelevance: minRelevance)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let buckets = Dictionary(grouping: items) { utc.startOfDay(for: $0.publishedAt) }
        let points = buckets.keys.sorted().map { day -> SentimentTrendPoint in
            let scores = buckets[day]!.map { ($0.compound ?? 0) * ($0.sourceWeight ?? 1) }
            return SentimentTrendPoint(bucket: day, meanCompound: Analytics.mean(scores), articleCount: scores.count)
        }
        return SentimentTrend(ticker: ticker.uppercased(), points: points)
    }

    // MARK: - Price

    func priceBars(ticker: String, limit: Int) async throws -> [PriceBar] {
        Array(try await yahoo.bars(ticker: ticker).suffix(limit))
    }

    func riskMetrics(ticker: String, benchmark: String = "SPY", days: Int = 365) async throws -> RiskMetrics {
        async let bars = yahoo.bars(ticker: ticker)
        async let bench = yahoo.bars(ticker: benchmark)
        return Analytics.riskMetrics(bars: try await bars, benchmark: try await bench)
    }

    // MARK: - Prediction

    func predictSync(ticker: String, horizonDays: Int) async throws -> Prediction {
        async let bars = yahoo.bars(ticker: ticker)
        async let one = relevant(ticker: ticker, since: daysAgo(1), minRelevance: 0.35)
        async let seven = relevant(ticker: ticker, since: daysAgo(7), minRelevance: 0.35)
        async let inHorizon = relevant(ticker: ticker, since: daysAgo(Double(horizonDays)), minRelevance: 0.35)
        async let raw = store.articles(ticker: ticker)

        let allArticles = try await raw
        let week = allArticles.filter { $0.publishedAt >= daysAgo(7) }.map { $0.compound ?? 0 }
        return Analytics.predict(
            ticker: ticker,
            horizonDays: horizonDays,
            signal: signal(try await inHorizon, days: Double(horizonDays)),
            ewma1d: signal(try await one, days: 1),
            ewma7d: signal(try await seven, days: 7),
            sentimentVolatility: Analytics.std(week),
            articleVolume24h: Double(allArticles.filter { $0.publishedAt >= daysAgo(1) }.count),
            price: Analytics.priceFeatures(bars: try await bars)
        )
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Double) -> Date { now().addingTimeInterval(-days * 86_400) }

    /// Recency-weighted sentiment of `items` for a window/horizon of `days` (half-life = days / 3).
    private func signal(_ items: [Article], days: Double) -> Double {
        let t = now()
        return Analytics.decayedMean(
            items.map { (value: ($0.compound ?? 0) * ($0.sourceWeight ?? 1), ageDays: t.timeIntervalSince($0.publishedAt) / 86_400) },
            halfLifeDays: days / 3
        )
    }

    /// Cached + fresh articles since `since`, headline-deduped (newest kept), scored for
    /// relevance to `ticker` and filtered at `minRelevance`. Newest first.
    private func relevant(ticker: String, since: Date, minRelevance: Double) async throws -> [Article] {
        var seen = Set<String>()
        var out: [Article] = []
        for article in try await store.articles(ticker: ticker) where article.publishedAt >= since {
            guard seen.insert(Analytics.dedupKey(article.headline)).inserted else { continue }
            let score = Analytics.relevance(ticker: ticker, headline: article.headline, symbols: article.symbols ?? [])
            guard score >= minRelevance else { continue }
            out.append(Article(
                id: article.id, url: article.url, headline: article.headline, summary: article.summary,
                body: article.body, source: article.source, publishedAt: article.publishedAt,
                sentimentLabel: article.sentimentLabel, compound: article.compound,
                relevanceScore: (score * 10_000).rounded() / 10_000, sourceWeight: article.sourceWeight,
                nearEarnings: article.nearEarnings, isSecFiling: article.isSecFiling, symbols: article.symbols
            ))
        }
        return out
    }
}
