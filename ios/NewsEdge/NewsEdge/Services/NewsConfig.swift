import Foundation

/// Tuning knobs for event grouping, storylines and embeddings, from data/news_config.json (shared with the web app,
/// synced by scripts/sync_news_profiles.py). Nothing else should hard-code these numbers.
struct NewsConfig: Decodable {
    struct Events: Decodable {
        struct Lexical: Decodable { let jaccard: Double; let overlap: Double; let minOverlapTokens: Int }
        struct OutletWeight: Decodable { let slope: Double; let cap: Double }
        let windowHours: Double
        let lexical: Lexical
        let outletWeight: OutletWeight
    }
    struct Storylines: Decodable {
        let windowHours: Double, contextDays: Double
        let minEvents: Int, minLocal: Int, minOutside: Int, noBaselineLocal: Int
        let dampingFloor: Double, minRate: Double, minBurst: Double, noBaselineRate: Double
    }
    struct Embedding: Decodable {
        let model: String
        let dimension: Int, maxTokens: Int
        let prefixCompanyWhenMissing: Bool
    }
    let events: Events
    let storylines: Storylines
    let embedding: Embedding

    static let shared: NewsConfig = {
        guard let url = Bundle.main.url(forResource: "NewsConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { preconditionFailure("NewsConfig.json missing from the bundle") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(NewsConfig.self, from: data) } catch { preconditionFailure("NewsConfig.json: \(error)") }
    }()
}
