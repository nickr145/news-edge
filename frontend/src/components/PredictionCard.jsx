const FEATURE_LABELS = {
  ewma_sentiment_1d: 'Sentiment 1d',
  ewma_sentiment_7d: 'Sentiment 7d',
  sentiment_volatility: 'Sent. volatility',
  article_volume_24h: 'News volume',
  rsi_14: 'RSI (14)',
  momentum_5d: 'Momentum 5d',
  bb_position: 'Bollinger band',
  volume_ratio: 'Volume ratio',
}

function Drivers({ importances }) {
  if (!importances) return null

  const meta = importances.__model || {}
  const isFallback = meta.version === 'fallback_rule_v2'

  const entries = Object.entries(importances)
    .filter(([k]) => !k.startsWith('__'))
    .map(([k, v]) => ({ key: k, label: FEATURE_LABELS[k] || k, value: Number(v) }))
    .sort((a, b) => Math.abs(b.value) - Math.abs(a.value))
    .slice(0, 5)

  if (!entries.length) return null

  const maxAbs = Math.max(...entries.map((e) => Math.abs(e.value)), 1e-9)

  return (
    <div className="drivers">
      <div className="drivers-title">
        {isFallback ? 'Feature values' : 'What moved the signal'}
        {!isFallback && <span className="drivers-tag">XGB · SHAP</span>}
      </div>
      {entries.map(({ key, label, value }) => {
        const pct = Math.round((Math.abs(value) / maxAbs) * 100)
        const dir = value >= 0 ? 'pos' : 'neg'
        return (
          <div key={key} className="driver-row">
            <span className="driver-label">{label}</span>
            <div className="driver-track" aria-hidden="true">
              <div className={`driver-bar ${dir}`} style={{ width: `${pct}%` }} />
            </div>
            <span className={`driver-val ${value >= 0 ? 'up' : 'down'}`}>{value >= 0 ? '+' : '−'}{Math.abs(value).toFixed(3)}</span>
          </div>
        )
      })}
    </div>
  )
}

/** Inputs behind the signal (the verdict itself lives in the strip above), plus horizon and re-run. */
export default function PredictionCard({ prediction, onPredict, predicting, horizonDays, onHorizonChange }) {
  return (
    <div className="card">
      <h2 className="card-title">Signal inputs</h2>
      {prediction ? (
        <>
          <div className="kv">
            <div className="kv-row">
              <span className="kv-label">Sentiment score</span>
              <span className="kv-value">{Number(prediction.sentiment_score || 0).toFixed(3)}</span>
            </div>
            <div className="kv-row">
              <span className="kv-label">RSI (14)</span>
              <span className="kv-value">{prediction.price_rsi?.toFixed?.(1) ?? '—'}</span>
            </div>
          </div>
          <Drivers importances={prediction.feature_importances} />
        </>
      ) : (
        <p className="muted-text">{predicting ? 'Calculating…' : 'Run a prediction to see what drives the signal.'}</p>
      )}
      <div className="model-controls">
        <label className="field">
          Horizon
          <select className="select" value={horizonDays} onChange={(e) => onHorizonChange(Number(e.target.value))}>
            <option value={1}>1 day</option>
            <option value={5}>5 days</option>
            <option value={14}>14 days</option>
          </select>
        </label>
        <button className="btn btn--primary" onClick={onPredict} disabled={predicting}>
          {predicting ? 'Analyzing…' : prediction ? 'Run again' : 'Run prediction'}
        </button>
      </div>
    </div>
  )
}
