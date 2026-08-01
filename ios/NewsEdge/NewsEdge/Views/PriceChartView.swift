import SwiftUI
import Charts

/// Ports PriceChart.jsx. Swift Charts has no native dual-y-axis, so instead of
/// rescaling sentiment into the price domain (which distorts both series),
/// this shows two synced mini-charts sharing the same date range: price on
/// its own $ scale, sentiment on its own -1...1 scale directly below.
struct PriceChartView: View {
    let bars: [PriceBar]
    let trend: SentimentTrend?

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private var sentimentByDay: [Date: Double] {
        guard let points = trend?.points else { return [:] }
        var map: [Date: Double] = [:]
        for point in points {
            map[calendar.startOfDay(for: point.bucket)] = point.meanCompound
        }
        return map
    }

    private var chartBars: [PriceBar] {
        guard let sentStart = sentimentByDay.keys.min() else { return bars }
        return bars.filter { calendar.startOfDay(for: $0.timestamp) >= sentStart }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price & Sentiment").font(.headline)

            if chartBars.isEmpty {
                Text("No price data available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(chartBars) { bar in
                    LineMark(
                        x: .value("Day", bar.timestamp),
                        y: .value("Close", bar.close)
                    )
                    .foregroundStyle(Theme.info)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .frame(height: 140)

                Chart {
                    ForEach(chartBars) { bar in
                        if let score = sentimentByDay[calendar.startOfDay(for: bar.timestamp)] {
                            LineMark(
                                x: .value("Day", bar.timestamp),
                                y: .value("Sentiment", score)
                            )
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.monotone)
                        }
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(dash: [3, 3]))
                }
                .chartYScale(domain: -1...1)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 90)
            }
        }
    }
}

#Preview {
    PriceChartView(bars: [], trend: nil)
        .card()
        .padding()
}
