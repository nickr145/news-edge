import Foundation
import NaturalLanguage

/// On-device port of the backend's pure computation:
/// app/utils/{stats,relevance,news_quality}.py, app/services/{analytics,price_data,prediction}.py.
/// Keep numerically in step with those files (sample std/cov, EWMA alpha 0.3).
enum Analytics {
    // MARK: - Stats (app/utils/stats.py)

    static func mean(_ v: [Double]) -> Double {
        v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    /// Sample standard deviation (n-1), like the backend and pandas.
    static func std(_ v: [Double]) -> Double {
        guard v.count >= 2 else { return 0 }
        let m = mean(v)
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)).squareRoot()
    }

    static func ewma(_ v: [Double], alpha: Double = 0.3) -> Double {
        guard var acc = v.first else { return 0 }
        for x in v.dropFirst() { acc = alpha * x + (1 - alpha) * acc }
        return acc
    }

    // MARK: - Sentiment

    /// FinBERT (Core ML) when bundled, else Apple's general-purpose NLTagger. -1...1.
    static func sentiment(_ text: String) -> Double {
        FinBERTScorer.shared?.score(text) ?? nlTaggerSentiment(text)
    }

    static func nlTaggerSentiment(_ text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return tag.flatMap { Double($0.rawValue) } ?? 0
    }

    static func label(_ compound: Double) -> String {
        compound > 0.05 ? "POSITIVE" : compound < -0.05 ? "NEGATIVE" : "NEUTRAL"
    }

    // MARK: - News quality (app/utils/news_quality.py, relevance.py)

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Headline with trailing publisher attribution ("- Reuters") stripped, normalized.
    static func dedupKey(_ headline: String) -> String {
        normalize(headline.replacingOccurrences(
            of: "\\s*[-–|]\\s*[A-Za-z][\\w\\s\\.&]{1,40}$", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces))
    }

    private static let sourceWeights = ["reuters": 1.25, "bloomberg": 1.25, "cnbc": 1.1, "benzinga": 0.95]

    static func sourceWeight(_ source: String?) -> Double {
        sourceWeights[normalize(source ?? "")] ?? 1.0
    }

    /// Yahoo writes share classes with a dash (`BRK-B`); users and the catalog use `BRK.B`.
    static func yahooSymbol(_ ticker: String) -> String {
        ticker.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: ".", with: "-")
    }

    static func relevance(ticker: String, headline: String, symbols: [String]) -> Double {
        let t = ticker.lowercased()
        let h = headline.lowercased()
        let syms = symbols.map(yahooSymbol)
        var score = 0.0
        if syms.contains(yahooSymbol(ticker)) { score += 0.45 }
        if h.contains(t) { score += 0.35 }
        if !syms.isEmpty { score -= min(0.25, 0.04 * Double(max(syms.count - 1, 0))) }
        if h.contains(t) { score += 0.05 }
        return max(0, min(1, score))
    }

    // MARK: - Price math (app/services/price_data.py)

    static func riskMetrics(bars: [PriceBar], benchmark: [PriceBar]) -> RiskMetrics {
        let zero = RiskMetrics(annualizedVolatility: 0, betaToBenchmark: 0, maxDrawdown: 0, highWaterMark: 0, cumulativeReturn: 0)
        guard bars.count >= 30, benchmark.count >= 30 else { return zero }

        func dayKey(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 86_400) }
        func returns(_ b: [PriceBar]) -> [(day: Int, r: Double)] {
            zip(b, b.dropFirst()).map { (dayKey($1.timestamp), $1.close / $0.close - 1) }
        }
        let benchByDay = Dictionary(returns(benchmark).map { ($0.day, $0.r) }, uniquingKeysWith: { $1 })
        let merged = returns(bars).compactMap { p in benchByDay[p.day].map { (p.r, $0) } }
        guard merged.count >= 2 else { return zero }

        let r = merged.map(\.0), b = merged.map(\.1)
        let mr = mean(r), mb = mean(b)
        let cov = zip(r, b).reduce(0) { $0 + ($1.0 - mr) * ($1.1 - mb) } / Double(r.count - 1)
        let varB = std(b) * std(b)

        let closes = bars.map(\.close)
        var runMax = -Double.infinity, maxDD = 0.0
        for c in closes {
            runMax = max(runMax, c)
            maxDD = min(maxDD, c / runMax - 1)
        }
        return RiskMetrics(
            annualizedVolatility: std(r) * 252.0.squareRoot(),
            betaToBenchmark: varB > 0 ? cov / varB : 0,
            maxDrawdown: maxDD,
            highWaterMark: runMax,
            cumulativeReturn: closes[0] != 0 ? closes[closes.count - 1] / closes[0] - 1 : 0
        )
    }

    struct PriceFeatures: Equatable {
        var rsi14 = 50.0, momentum5d = 0.0, bbPosition = 0.5, volumeRatio = 1.0
    }

    static func priceFeatures(bars: [PriceBar]) -> PriceFeatures {
        guard bars.count >= 30 else { return PriceFeatures() }
        let close = bars.map(\.close), volume = bars.map(\.volume)
        let n = close.count

        let deltas = zip(close.dropFirst(), close).map { $0 - $1 }.suffix(14)
        let gain = deltas.map { max($0, 0) }.reduce(0, +) / 14
        var loss = deltas.map { max(-$0, 0) }.reduce(0, +) / 14
        if loss == 0 { loss = 1e-9 }
        let rsi = 100 - 100 / (1 + gain / loss)

        let window = Array(close.suffix(20))
        let ma = mean(window), sd = std(window)
        let lower = ma - 2 * sd, upper = ma + 2 * sd
        let width = upper - lower == 0 ? 1e-9 : upper - lower
        let bb = max(0, min(1, (close[n - 1] - lower) / width))

        let avgVol = mean(Array(volume.suffix(20)))
        return PriceFeatures(
            rsi14: rsi,
            momentum5d: close[n - 1] / close[n - 6] - 1,
            bbPosition: bb,
            volumeRatio: volume[n - 1] / (avgVol == 0 ? 1e-9 : avgVol)
        )
    }

    // MARK: - Prediction (fallback rule from app/services/prediction.py)

    static func predict(
        ticker: String,
        horizonDays: Int,
        ewma1d: Double,
        ewma7d: Double,
        sentimentVolatility: Double,
        articleVolume24h: Double,
        price: PriceFeatures,
        now: Date = Date()
    ) -> Prediction {
        let recommendation = ewma1d > 0.15 ? "RISE" : ewma1d < -0.15 ? "FALL" : "STABLE"
        let features: [String: JSONValue] = [
            "ewma_sentiment_1d": .number(ewma1d),
            "ewma_sentiment_7d": .number(ewma7d),
            "sentiment_volatility": .number(sentimentVolatility),
            "article_volume_24h": .number(articleVolume24h),
            "rsi_14": .number(price.rsi14),
            "momentum_5d": .number(price.momentum5d),
            "bb_position": .number(price.bbPosition),
            "volume_ratio": .number(price.volumeRatio),
            // ShapChartView keys its "Feature Values" mode off this exact version string.
            "__model": .object(["version": .string("fallback_rule_v2"), "reason": .string("on_device_rule")]),
        ]
        return Prediction(
            id: Int(now.timeIntervalSince1970),
            ticker: ticker.uppercased(),
            predictedAt: now,
            recommendation: recommendation,
            confidence: min(0.85, 0.52 + abs(ewma1d) * 0.35),
            sentimentScore: ewma1d,
            priceRsi: price.rsi14,
            featureImportances: features,
            horizonDays: horizonDays
        )
    }
}
