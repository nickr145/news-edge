import Foundation
import Testing
@testable import NewsEdge

/// Expected values were produced by running the original backend code
/// (app/utils/*, app/services/price_data.py) on the same synthetic inputs.
struct AnalyticsTests {
    private static func bars(base: Double, amp: Double, period: Double, drift: Double, volume: Bool = false) -> [PriceBar] {
        (0..<60).map { i in
            let close = base + amp * sin(Double(i) / period) + drift * Double(i)
            return PriceBar(
                timestamp: Date(timeIntervalSince1970: 1_767_225_600 + Double(i) * 86_400),
                open: close, high: close, low: close, close: close,
                volume: volume ? Double(1000 + 50 * (i % 7)) : 0
            )
        }
    }

    @Test func stats() {
        let x = [0.5, -0.2, 0.1, 0.8, -0.6]
        #expect(abs(Analytics.mean(x) - 0.12) < 1e-9)
        #expect(abs(Analytics.std(x) - 0.5540758070878028) < 1e-9)
        #expect(abs(Analytics.ewma(x) - 0.10217) < 1e-9)
        #expect(Analytics.ewma([]) == 0)
    }

    @Test func riskMetricsMatchBackend() {
        let risk = Analytics.riskMetrics(
            bars: Self.bars(base: 100, amp: 10, period: 5, drift: 0.1),
            benchmark: Self.bars(base: 400, amp: 20, period: 7, drift: 0.3)
        )
        #expect(abs(risk.annualizedVolatility - 0.21440983353406579) < 1e-9)
        #expect(abs(risk.betaToBenchmark - -0.003717400959689276) < 1e-9)
        #expect(abs(risk.maxDrawdown - -0.1663660238846164) < 1e-9)
        #expect(abs(risk.highWaterMark - 113.89358246623382) < 1e-9)
        #expect(abs(risk.cumulativeReturn - -0.010352508477712186) < 1e-9)
    }

    @Test func riskMetricsNeedEnoughBars() {
        let few = Array(Self.bars(base: 100, amp: 1, period: 5, drift: 0).prefix(10))
        #expect(Analytics.riskMetrics(bars: few, benchmark: few).annualizedVolatility == 0)
    }

    @Test func priceFeaturesMatchBackend() {
        let f = Analytics.priceFeatures(bars: Self.bars(base: 100, amp: 10, period: 5, drift: 0.1, volume: true))
        #expect(abs(f.rsi14 - 20.88933992202965) < 1e-6)
        #expect(abs(f.momentum5d - 0.03529750961078859) < 1e-9)
        #expect(abs(f.bbPosition - 0.356324167621198) < 1e-9)
        #expect(abs(f.volumeRatio - 1.0021786492374727) < 1e-9)
        #expect(Analytics.priceFeatures(bars: []) == Analytics.PriceFeatures())
    }

    @Test func dedupAndRelevanceMatchBackend() {
        #expect(Analytics.dedupKey("Apple hits record high - Reuters") == "apple hits record high")
        #expect(Analytics.dedupKey("Apple hits record high | Yahoo Finance") == "apple hits record high")
        #expect(abs(Analytics.relevance(ticker: "AAPL", headline: "AAPL jumps on earnings", symbols: ["AAPL", "MSFT", "NVDA"]) - 0.77) < 1e-9)
        #expect(Analytics.relevance(ticker: "AAPL", headline: "Tech stocks rally", symbols: ["NVDA"]) == 0)
    }

    @Test func predictionRule() {
        func rec(_ s: Double) -> Prediction {
            Analytics.predict(ticker: "aapl", horizonDays: 5, ewma1d: s, ewma7d: 0, sentimentVolatility: 0,
                              articleVolume24h: 0, price: .init())
        }
        #expect(rec(0.2).recommendation == "RISE")
        #expect(rec(-0.2).recommendation == "FALL")
        #expect(rec(0.15).recommendation == "STABLE")
        #expect(rec(0).confidence == 0.52)
        #expect(rec(5).confidence == 0.85)
        #expect(rec(0).ticker == "AAPL")
    }

    @Test func stableIDIsDeterministic() {
        #expect(YahooClient.stableID("abc") == YahooClient.stableID("abc"))
        #expect(YahooClient.stableID("abc") != YahooClient.stableID("abd"))
        #expect(YahooClient.stableID("abc") > 0)
    }
}
