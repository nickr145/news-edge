import SwiftUI

/// Ports PredictionCard.jsx.
struct PredictionCardView: View {
    let prediction: Prediction?
    let predicting: Bool
    @Binding var horizonDays: Int
    let onPredict: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendation").font(.headline)

            if let prediction {
                Text(prediction.recommendation)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.signalColor(prediction.recommendation))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Confidence").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(prediction.confidence, format: .percent.precision(.fractionLength(1)))
                            .font(.caption.monospacedDigit())
                    }
                    ProgressView(value: prediction.confidence)
                        .tint(Theme.signalColor(prediction.recommendation))
                }

                HStack {
                    metric("Sentiment", String(format: "%.3f", prediction.sentimentScore))
                    metric("RSI", String(format: "%.1f", prediction.priceRsi))
                    metric("Horizon", "\(prediction.horizonDays)d")
                }

                ShapChartView(importances: prediction.featureImportances)
            } else {
                Text("Run a prediction to see a BUY / HOLD / SELL signal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Horizon", selection: $horizonDays) {
                Text("1 day").tag(1)
                Text("5 days").tag(5)
                Text("14 days").tag(14)
            }
            .pickerStyle(.segmented)

            Button(action: onPredict) {
                Group {
                    if predicting {
                        ProgressView()
                    } else {
                        Text("Run Prediction")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(predicting)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

#Preview {
    PredictionCardView(prediction: nil, predicting: false, horizonDays: .constant(5), onPredict: {})
        .card()
        .padding()
}
