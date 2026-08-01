import SwiftUI

/// Ports the ShapChart sub-component of PredictionCard.jsx.
struct ShapChartView: View {
    let importances: [String: JSONValue]

    private static let featureLabels: [String: String] = [
        "ewma_sentiment_1d": "Sentiment 1d",
        "ewma_sentiment_7d": "Sentiment 7d",
        "sentiment_volatility": "Sent. Volatility",
        "article_volume_24h": "News Volume",
        "rsi_14": "RSI (14)",
        "momentum_5d": "Momentum 5d",
        "bb_position": "Bollinger Band",
        "volume_ratio": "Volume Ratio",
    ]

    private struct Entry: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    private var entries: [Entry] {
        importances
            .filter { !$0.key.hasPrefix("__") }
            .compactMap { key, value -> Entry? in
                guard let number = value.doubleValue else { return nil }
                return Entry(id: key, label: Self.featureLabels[key] ?? key, value: number)
            }
            .sorted { abs($0.value) > abs($1.value) }
            .prefix(5)
            .map { $0 }
    }

    private var isFallback: Bool {
        if case .object(let meta)? = importances["__model"],
           case .string(let version)? = meta["version"] {
            return version == "fallback_rule_v2"
        }
        return false
    }

    var body: some View {
        let currentEntries = entries
        if !currentEntries.isEmpty {
            let maxAbs = max(currentEntries.map { abs($0.value) }.max() ?? 0, 1e-9)
            VStack(alignment: .leading, spacing: 6) {
                Text(isFallback ? "Feature Values" : "SHAP Explanations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(currentEntries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.label)
                            .font(.caption2)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.value >= 0 ? Theme.accent : Theme.danger)
                                .frame(width: geo.size.width * min(abs(entry.value) / maxAbs, 1))
                        }
                        .frame(height: 8)
                        Text(entry.value, format: .number.sign(strategy: .always()).precision(.fractionLength(3)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(entry.value >= 0 ? Theme.accent : Theme.danger)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }
}
