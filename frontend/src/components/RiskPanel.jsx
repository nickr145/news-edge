import { signed } from '../lib/format'

export default function RiskPanel({ risk }) {
  const ret = Number(risk?.cumulative_return || 0) * 100

  return (
    <div className="card">
      <h2 className="card-title">Risk metrics</h2>
      {risk ? (
        <div className="kv">
          <div className="kv-row">
            <span className="kv-label">Volatility (annualized)</span>
            <span className="kv-value">{(Number(risk.annualized_volatility || 0) * 100).toFixed(2)}%</span>
          </div>
          <div className="kv-row">
            <span className="kv-label">Beta vs SPY</span>
            <span className="kv-value">{Number(risk.beta_to_benchmark || 0).toFixed(2)}</span>
          </div>
          <div className="kv-row">
            <span className="kv-label">Max drawdown</span>
            <span className="kv-value down">{(Number(risk.max_drawdown || 0) * 100).toFixed(2)}%</span>
          </div>
          <div className="kv-row">
            <span className="kv-label">High-water mark</span>
            <span className="kv-value">${Number(risk.high_water_mark || 0).toFixed(2)}</span>
          </div>
          <div className="kv-row">
            <span className="kv-label">Cumulative return</span>
            <span className={`kv-value ${ret >= 0 ? 'up' : 'down'}`}>{signed(ret)}%</span>
          </div>
        </div>
      ) : (
        <p className="muted-text">No risk data available.</p>
      )}
    </div>
  )
}
