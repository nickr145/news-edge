import Foundation

// Mirrors app/schemas/fundamentals.py
// Not yet called by the web frontend, but kept in sync with the backend contract.

struct EarningsEvent: Codable, Identifiable, Equatable {
    let id: Int
    let ticker: String
    let reportDate: Date
    let fiscalDateEnding: String?
    let estimatedEps: Double?
    let actualEps: Double?
    let surprisePct: Double?

    enum CodingKeys: String, CodingKey {
        case id, ticker
        case reportDate = "report_date"
        case fiscalDateEnding = "fiscal_date_ending"
        case estimatedEps = "estimated_eps"
        case actualEps = "actual_eps"
        case surprisePct = "surprise_pct"
    }
}

struct SecFiling: Codable, Identifiable, Equatable {
    let id: Int
    let ticker: String
    let formType: String
    let filedAt: Date
    let description: String?
    let filingUrl: String
    let articleId: Int?

    enum CodingKeys: String, CodingKey {
        case id, ticker, description
        case formType = "form_type"
        case filedAt = "filed_at"
        case filingUrl = "filing_url"
        case articleId = "article_id"
    }
}
