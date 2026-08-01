import SwiftUI

/// Ports RiskPanel.jsx.
struct RiskPanelView: View {
    let risk: RiskMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Risk Metrics").font(.headline)
            if let risk {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metric("Volatility", percent(risk.annualizedVolatility))
                    metric("Beta (SPY)", String(format: "%.2f", risk.betaToBenchmark))
                    metric("Max Drawdown", percent(risk.maxDrawdown), color: Theme.danger)
                    metric("High Water Mark", currency(risk.highWaterMark))
                }
                metric(
                    "Cumulative Return",
                    percent(risk.cumulativeReturn),
                    color: risk.cumulativeReturn >= 0 ? Theme.accent : Theme.danger
                )
            } else {
                Text("No risk data available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(color)
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
    private func currency(_ value: Double) -> String { String(format: "$%.2f", value) }
}

#Preview {
    RiskPanelView(risk: nil)
        .card()
        .padding()
}
