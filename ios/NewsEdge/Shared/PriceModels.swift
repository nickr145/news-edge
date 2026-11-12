import Foundation

// Mirrors the raw dict responses from app/api/routes_price.py
// (these endpoints return plain dicts / dataclasses, not Pydantic schemas).

struct PriceBar: Codable, Identifiable, Equatable {
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var id: Date { timestamp }
}

/// Mirrors `RiskMetrics` in app/services/price_data.py.
struct RiskMetrics: Codable, Equatable {
    let annualizedVolatility: Double
    let betaToBenchmark: Double
    let maxDrawdown: Double
    let highWaterMark: Double
    let cumulativeReturn: Double

    enum CodingKeys: String, CodingKey {
        case annualizedVolatility = "annualized_volatility"
        case betaToBenchmark = "beta_to_benchmark"
        case maxDrawdown = "max_drawdown"
        case highWaterMark = "high_water_mark"
        case cumulativeReturn = "cumulative_return"
    }
}
