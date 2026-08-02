import SwiftUI
import Charts

/// Ports SentimentPanel.jsx.
struct SentimentPanelView: View {
    let summary: SentimentSummary?
    let trend: SentimentTrend?
    var isLoading: Bool = false

    private var labelDistribution: [(label: String, value: Int)] {
        (summary?.labelDistribution ?? [:])
            .map { (label: $0.key, value: $0.value) }
            .sorted { $0.label < $1.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentiment").font(.headline).foregroundStyle(Theme.text)
            if summary == nil && isLoading {
                LoadingOrEmptyView(isLoading: true, message: "")
            } else {
                statRow
            }

            if let points = trend?.points, !points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Sentiment Trend")
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
                            .foregroundStyle(Theme.borderMid)
                            .lineStyle(StrokeStyle(dash: [3, 3]))
                    }
                    .chartYScale(domain: -1...1)
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 140)
                }
            }

            if !labelDistribution.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Label Distribution")
                    Chart(labelDistribution, id: \.label) { entry in
                        BarMark(
                            x: .value("Label", entry.label),
                            y: .value("Count", entry.value)
                        )
                        .foregroundStyle(Theme.warn)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.border)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }

    private var statRow: some View {
        HStack(alignment: .top) {
            statCell("EWMA", summary?.ewmaCompound)
            statCell("Mean", summary?.meanCompound)
            statCell("Std Dev", summary?.stdCompound)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Articles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text("\(summary?.count ?? 0)")
                    .font(.mono(15, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func statCell(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value.map { String(format: "%.3f", $0) } ?? "0.000")
                .font(.mono(15, weight: .medium))
                .foregroundStyle(Theme.text)
        }
    }
}

#Preview {
    SentimentPanelView(summary: nil, trend: nil)
        .card()
        .padding()
        .background(Theme.background)
}
