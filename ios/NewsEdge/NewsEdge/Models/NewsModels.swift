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
    let sentimentLabel: String?
    let compound: Double?
    let relevanceScore: Double?
    let sourceWeight: Double?
    let nearEarnings: Bool?
    let isSecFiling: Bool?

    enum CodingKeys: String, CodingKey {
        case id, url, headline, summary, body, source, compound
        case publishedAt = "published_at"
        case sentimentLabel = "sentiment_label"
        case relevanceScore = "relevance_score"
        case sourceWeight = "source_weight"
        case nearEarnings = "near_earnings"
        case isSecFiling = "is_sec_filing"
    }
}

struct SentimentSummary: Codable, Equatable {
    let ticker: String
    let count: Int
    let meanCompound: Double
    let stdCompound: Double
    let ewmaCompound: Double
    let labelDistribution: [String: Int]

    enum CodingKeys: String, CodingKey {
        case ticker, count
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

/// Response body of `POST /api/news/subscribe/{ticker}`.
struct SubscribeResponse: Codable, Equatable {
    let ok: Bool
    let ticker: String
    let subscribedTickers: [String]
    let backfillDays: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case ok, ticker, status
        case subscribedTickers = "subscribed_tickers"
        case backfillDays = "backfill_days"
    }
}
