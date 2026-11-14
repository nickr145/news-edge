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
        try await events(ticker: ticker, since: daysAgo(Double(days)), minRelevance: minRelevance)
            .prefix(limit)
            .map { e in
                var a = e.rep
                a.emb = nil // embeddings stay in the cache
                a.relevanceScore = (e.relevance * 10_000).rounded() / 10_000
                a.channel = e.channel
                a.eventSize = e.size
                a.eventOutlets = e.outlets
                a.storyline = e.storyline
                a.storyRank = e.storyRank
                a.storyDamp = (e.damp * 10_000).rounded() / 10_000
                return a
            }
    }

    func sentimentSummary(
        ticker: String,
        days: Int,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> SentimentSummary {
        let evs = try await events(ticker: ticker, since: daysAgo(Double(days)), minRelevance: minRelevance)
        let values = evs.map(\.value), weights = evs.map(\.weight)
        var labels = ["POSITIVE": 0, "NEUTRAL": 0, "NEGATIVE": 0]
        for e in evs { labels[Analytics.label(e.value), default: 0] += 1 }
        let summary = SentimentSummary(
            ticker: ticker.uppercased(),
            count: evs.count,
            articleCount: evs.reduce(0) { $0 + $1.size },
            meanCompound: Analytics.weightedMean(values, weights),
            stdCompound: Analytics.weightedStd(values, weights),
            ewmaCompound: signal(evs, days: Double(days)),
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
        let evs = try await events(ticker: ticker, since: daysAgo(Double(hours) / 24), minRelevance: minRelevance)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let buckets = Dictionary(grouping: evs) { utc.startOfDay(for: $0.time) }
        let points = buckets.keys.sorted().map { day -> SentimentTrendPoint in
            let group = buckets[day]!
            return SentimentTrendPoint(bucket: day, meanCompound: Analytics.weightedMean(group.map(\.value), group.map(\.weight)), articleCount: group.count)
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
        async let one = events(ticker: ticker, since: daysAgo(1), minRelevance: 0.35)
        async let seven = events(ticker: ticker, since: daysAgo(7), minRelevance: 0.35)
        async let inHorizon = events(ticker: ticker, since: daysAgo(Double(horizonDays)), minRelevance: 0.35)
        async let raw = store.articles(ticker: ticker)

        let allArticles = try await raw
        let sevenDay = try await seven
        return Analytics.predict(
            ticker: ticker,
            horizonDays: horizonDays,
            signal: signal(try await inHorizon, days: Double(horizonDays)),
            ewma1d: signal(try await one, days: 1),
            ewma7d: signal(sevenDay, days: 7),
            sentimentVolatility: Analytics.weightedStd(sevenDay.map(\.value), sevenDay.map(\.weight)),
            articleVolume24h: Double(allArticles.filter { $0.publishedAt >= daysAgo(1) }.count),
            price: Analytics.priceFeatures(bars: try await bars)
        )
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Double) -> Date { now().addingTimeInterval(-days * 86_400) }

    /// Recency-weighted sentiment of events for a window/horizon of `days` (half-life = days / 3).
    private func signal(_ events: [NewsEvent], days: Double) -> Double {
        let t = now()
        return Analytics.decayedMean(
            events.map { (value: $0.value, ageDays: t.timeIntervalSince($0.time) / 86_400, weight: $0.weight) },
            halfLifeDays: days / 3
        )
    }

    /// Window + relevance (direct or indirect) + event grouping. Every aggregate works on events, so a story echoed by
    /// many outlets is one vote with a bounded coverage boost, and indirect channels carry their own sign and weight.
    private func events(ticker: String, since: Date, minRelevance: Double) async throws -> [NewsEvent] {
        let profile = NewsEvents.profile(for: ticker, companyName: TickerCatalog.name(for: ticker))
        var items: [ExposedArticle] = []
        // Storyline detection needs context (what is normal vs a burst), so look back at least 30 days even for a 1-day window.
        let context = min(since, now().addingTimeInterval(-NewsConfig.shared.storylines.contextDays * 86_400))
        for a in try await store.articles(ticker: ticker) where a.publishedAt >= context {
            guard let ex = NewsEvents.exposure(profile: profile, headline: a.headline, symbols: a.symbols ?? []),
                  ex.relevance >= minRelevance else { continue }
            items.append(ExposedArticle(article: a, exposure: ex, time: a.publishedAt, value: (a.compound ?? 0) * (a.sourceWeight ?? 1) * ex.sign))
        }
        let grouped = NewsEvents.groupEvents(items, ignore: NewsEvents.ignoreTokens(profile))
        return NewsEvents.dampStorylines(grouped, exclude: NewsEvents.storylineExclusions(profile)).filter { $0.time >= since }
    }
}
