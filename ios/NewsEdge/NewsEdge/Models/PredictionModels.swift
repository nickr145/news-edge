import Foundation

// Mirrors app/schemas/prediction.py

struct PredictionRequest: Encodable {
    var horizonDays: Int = 5

    enum CodingKeys: String, CodingKey {
        case horizonDays = "horizon_days"
    }
}

struct Prediction: Codable, Identifiable, Equatable {
    let id: Int
    let ticker: String
    let predictedAt: Date
    let recommendation: String
    let confidence: Double
    let sentimentScore: Double
    let priceRsi: Double
    /// Untyped on the backend (`dict`); numeric feature contributions plus a
    /// `__model` metadata entry. See ShapChart in the web frontend for usage.
    let featureImportances: [String: JSONValue]
    let horizonDays: Int

    enum CodingKeys: String, CodingKey {
        case id, ticker, recommendation, confidence
        case predictedAt = "predicted_at"
        case sentimentScore = "sentiment_score"
        case priceRsi = "price_rsi"
        case featureImportances = "feature_importances"
        case horizonDays = "horizon_days"
    }
}
