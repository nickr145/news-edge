import SwiftUI

/// Ports PredictionCard.jsx.
struct PredictionCardView: View {
    let prediction: Prediction?
    let predicting: Bool
    @Binding var horizonDays: Int
    let onPredict: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendation").font(.headline).foregroundStyle(Theme.text)

            if let prediction {
                Text(prediction.recommendation)
                    .font(.mono(30, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.signalColor(prediction.recommendation))
                    .shadow(color: Theme.signalColor(prediction.recommendation).opacity(0.4), radius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Confidence")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(prediction.confidence, format: .percent.precision(.fractionLength(1)))
                            .font(.mono(13))
                            .foregroundStyle(Theme.text)
                    }
                    ProgressView(value: prediction.confidence)
                        .tint(Theme.signalColor(prediction.recommendation))
                }

                HStack(spacing: 8) {
                    metric("Sentiment", String(format: "%.3f", prediction.sentimentScore))
                    metric("RSI", String(format: "%.1f", prediction.priceRsi))
                    metric("Horizon", "\(prediction.horizonDays)d")
                }

                ShapChartView(importances: prediction.featureImportances)
            } else {
                Text("Run a prediction to see a RISE / STABLE / FALL signal.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            Picker("Horizon", selection: $horizonDays) {
                Text("1 day").tag(1)
                Text("5 days").tag(5)
                Text("14 days").tag(14)
            }
            .pickerStyle(.segmented)
            .tint(Theme.accent)

            Button(action: onPredict) {
                Group {
                    if predicting {
                        ProgressView()
                            .tint(Theme.background)
                    } else {
                        Text("Run Prediction")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.background)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .opacity(predicting ? 0.4 : 1)
            .disabled(predicting)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.mono(15, weight: .medium))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricCell()
    }
}

#Preview {
    PredictionCardView(prediction: nil, predicting: false, horizonDays: .constant(5), onPredict: {})
        .card()
        .padding()
        .background(Theme.background)
}
