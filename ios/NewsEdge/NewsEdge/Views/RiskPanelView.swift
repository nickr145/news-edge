import SwiftUI

/// Ports RiskPanel.jsx.
struct RiskPanelView: View {
    let risk: RiskMetrics?
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Risk Metrics").font(.headline).foregroundStyle(Theme.text)
            if let risk {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LoadingOrEmptyView(isLoading: isLoading, message: "No risk data available.")
            }
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.mono(16, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricCell()
    }

    private func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
    private func currency(_ value: Double) -> String { String(format: "$%.2f", value) }
}

#Preview {
    RiskPanelView(risk: nil)
        .card()
        .padding()
        .background(Theme.background)
}
