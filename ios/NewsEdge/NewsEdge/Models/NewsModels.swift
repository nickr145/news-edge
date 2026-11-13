import Foundation

// Mirrors app/schemas/news.py

struct Article: Codable, Identifiable, Equatable {
    let id: Int
    let url: String
    let headline: String
    let summary: String?
    let body: String?
    let source: String?
    let publishedAt: Date
    var sentimentLabel: String?
    var compound: Double?
    var relevanceScore: Double?
    let sourceWeight: Double?
    let nearEarnings: Bool?
    let isSecFiling: Bool?
    /// Tickers Yahoo tagged the article with; feeds `Analytics.relevance`.
    var symbols: [String]? = nil
    /// Set on articles returned by `APIClient.articles` (not stored): why it bears on the ticker
    /// ("direct", "people", "supply", "sector", "competitor", "macro") and how many articles/outlets the event had.
    var channel: String? = nil
    var eventSize: Int? = nil
    var eventOutlets: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, url, headline, summary, body, source, compound, symbols, channel
        case publishedAt = "published_at"
        case sentimentLabel = "sentiment_label"
        case relevanceScore = "relevance_score"
        case sourceWeight = "source_weight"
        case nearEarnings = "near_earnings"
        case isSecFiling = "is_sec_filing"
        case eventSize = "event_size"
        case eventOutlets = "event_outlets"
    }
}

struct SentimentSummary: Codable, Equatable {
    let ticker: String
    /// Distinct events (the same story from several outlets counts once).
    let count: Int
    var articleCount: Int? = nil
    let meanCompound: Double
    let stdCompound: Double
    let ewmaCompound: Double
    let labelDistribution: [String: Int]

    enum CodingKeys: String, CodingKey {
        case ticker, count
        case articleCount = "article_count"
        case meanCompound = "mean_compound"
        case stdCompound = "std_compound"
        case ewmaCompound = "ewma_compound"
        case labelDistribution = "label_distribution"
    }
}

struct SentimentTrendPoint: Codable, Identifiable, Equatable {
    let bucket: Date
    let meanCompound: Double
    let articleCount: Int

    var id: Date { bucket }

    enum CodingKeys: String, CodingKey {
        case bucket
        case meanCompound = "mean_compound"
        case articleCount = "article_count"
    }
}

struct SentimentTrend: Codable, Equatable {
    let ticker: String
    let points: [SentimentTrendPoint]
}
