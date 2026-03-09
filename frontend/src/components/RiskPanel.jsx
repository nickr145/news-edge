export default function RiskPanel({ risk }) {
  return (
    <section className="card">
      <h2>Risk Metrics</h2>
      {!risk && <p>No risk metrics available.</p>}
      {risk && (
        <div className="metrics-row">
          <div><small>Vol (ann.)</small><strong>{(Number(risk.annualized_volatility || 0) * 100).toFixed(2)}%</strong></div>
          <div><small>Beta (SPY)</small><strong>{Number(risk.beta_to_benchmark || 0).toFixed(2)}</strong></div>
          <div><small>Max DD</small><strong>{(Number(risk.max_drawdown || 0) * 100).toFixed(2)}%</strong></div>
          <div><small>HWM</small><strong>{Number(risk.high_water_mark || 0).toFixed(2)}</strong></div>
        </div>
      )}
    </section>
  )
}
