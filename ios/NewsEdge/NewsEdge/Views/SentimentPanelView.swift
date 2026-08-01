import SwiftUI
import Charts

/// Ports SentimentPanel.jsx.
struct SentimentPanelView: View {
    let summary: SentimentSummary?
    let trend: SentimentTrend?

    private var labelDistribution: [(label: String, value: Int)] {
        (summary?.labelDistribution ?? [:])
            .map { (label: $0.key, value: $0.value) }
            .sorted { $0.label < $1.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentiment").font(.headline)
            statRow

            if let points = trend?.points, !points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sentiment Trend").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(points) { point in
                            LineMark(
                                x: .value("Date", point.bucket),
                                y: .value("Score", point.meanCompound)
                            )
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.monotone)
                        }
                        RuleMark(y: .value("Zero", 0))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(dash: [3, 3]))
                    }
                    .chartYScale(domain: -1...1)
                    .frame(height: 140)
                }
            }

            if !labelDistribution.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label Distribution").font(.caption).foregroundStyle(.secondary)
                    Chart(labelDistribution, id: \.label) { entry in
                        BarMark(
                            x: .value("Label", entry.label),
                            y: .value("Count", entry.value)
                        )
                        .foregroundStyle(Theme.warn)
                        .cornerRadius(4)
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private var statRow: some View {
        HStack(alignment: .top) {
            statCell("EWMA", summary?.ewmaCompound)
            statCell("Mean", summary?.meanCompound)
            statCell("Std Dev", summary?.stdCompound)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Articles").font(.caption2).foregroundStyle(.secondary)
                Text("\(summary?.count ?? 0)").font(.callout.monospacedDigit())
            }
        }
    }

    private func statCell(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.3f", $0) } ?? "0.000")
                .font(.callout.monospacedDigit())
        }
    }
}

#Preview {
    SentimentPanelView(summary: nil, trend: nil)
        .card()
        .padding()
}
