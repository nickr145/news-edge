export default function RiskPanel({ risk }) {
  const ret = Number(risk?.cumulative_return || 0)

  return (
    <div className="card">
      <div className="panel-label">Risk Metrics</div>
      {risk ? (
        <div className="metric-grid">
          <div className="metric-cell">
            <span className="metric-label">Volatility</span>
            <span className="metric-value">{(Number(risk.annualized_volatility || 0) * 100).toFixed(2)}%</span>
          </div>
          <div className="metric-cell">
            <span className="metric-label">Beta (SPY)</span>
            <span className="metric-value">{Number(risk.beta_to_benchmark || 0).toFixed(2)}</span>
          </div>
          <div className="metric-cell">
            <span className="metric-label">Max Drawdown</span>
            <span className="metric-value danger">{(Number(risk.max_drawdown || 0) * 100).toFixed(2)}%</span>
          </div>
          <div className="metric-cell">
            <span className="metric-label">High Water Mark</span>
            <span className="metric-value">${Number(risk.high_water_mark || 0).toFixed(2)}</span>
          </div>
          <div className="metric-cell wide">
            <span className="metric-label">Cumulative Return</span>
            <span className={`metric-value ${ret >= 0 ? 'positive' : 'danger'}`}>
              {(ret * 100).toFixed(2)}%
            </span>
          </div>
        </div>
      ) : (
        <p className="muted-text">No risk data available.</p>
      )}
    </div>
  )
}
