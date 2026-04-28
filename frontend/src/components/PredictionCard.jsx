const FEATURE_LABELS = {
  ewma_sentiment_1d: 'Sentiment 1d',
  ewma_sentiment_7d: 'Sentiment 7d',
  sentiment_volatility: 'Sent. Volatility',
  article_volume_24h: 'News Volume',
  rsi_14: 'RSI (14)',
  momentum_5d: 'Momentum 5d',
  bb_position: 'Bollinger Band',
  volume_ratio: 'Volume Ratio',
}

function ShapChart({ importances }) {
  if (!importances) return null

  const meta = importances.__model || {}
  const isFallback = meta.version === 'fallback_rule_v2'

  const entries = Object.entries(importances)
    .filter(([k]) => !k.startsWith('__'))
    .map(([k, v]) => ({ key: k, label: FEATURE_LABELS[k] || k, value: Number(v) }))
    .sort((a, b) => Math.abs(b.value) - Math.abs(a.value))
    .slice(0, 5)

  if (!entries.length) return null

  const maxAbs = Math.max(...entries.map(e => Math.abs(e.value)), 1e-9)

  return (
    <div className="shap-section">
      <div className="shap-header">
        {isFallback ? 'Feature Values' : 'SHAP Explanations'}
        {!isFallback && <span className="shap-model-tag">XGB</span>}
      </div>
      {entries.map(({ key, label, value }) => {
        const pct = Math.round((Math.abs(value) / maxAbs) * 100)
        const dir = value >= 0 ? 'pos' : 'neg'
        return (
          <div key={key} className="shap-row">
            <span className="shap-label">{label}</span>
            <div className="shap-bar-track">
              <div className={`shap-bar ${dir}`} style={{ width: `${pct}%` }} />
            </div>
            <span className={`shap-val ${dir}`}>{value >= 0 ? '+' : ''}{value.toFixed(3)}</span>
          </div>
        )
      })}
    </div>
  )
}

export default function PredictionCard({ prediction, onPredict, predicting, horizonDays, onHorizonChange }) {
  const rec = prediction?.recommendation?.toLowerCase() || ''
  const confidence = prediction ? (prediction.confidence * 100).toFixed(1) : 0

  return (
    <div className="card">
      <div className="panel-label">Recommendation</div>
      {prediction ? (
        <>
          <div className={`signal-display ${rec}`}>{prediction.recommendation}</div>
          <div className="confidence-row">
            <span>Confidence</span>
            <span className="confidence-val">{confidence}%</span>
          </div>
          <div className="confidence-bar">
            <div className={`confidence-fill ${rec}`} style={{ width: `${confidence}%` }} />
          </div>
          <div className="metric-grid">
            <div className="metric-cell">
              <span className="metric-label">Sentiment</span>
              <span className="metric-value">{Number(prediction.sentiment_score || 0).toFixed(3)}</span>
            </div>
            <div className="metric-cell">
              <span className="metric-label">RSI</span>
              <span className="metric-value">{prediction.price_rsi?.toFixed?.(1) ?? '—'}</span>
            </div>
            <div className="metric-cell wide">
              <span className="metric-label">Horizon</span>
              <span className="metric-value">{prediction.horizon_days ?? '—'} days</span>
            </div>
          </div>
          <ShapChart importances={prediction.feature_importances} />
        </>
      ) : (
        <p className="muted-text" style={{ marginBottom: '0.75rem' }}>Run a prediction to see a BUY / HOLD / SELL signal.</p>
      )}
      <div className="horizon-row">
        <span className="ctrl-label">Horizon</span>
        <select
          className="ctrl-select"
          value={horizonDays}
          onChange={(e) => onHorizonChange(Number(e.target.value))}
        >
          <option value={1}>1 day</option>
          <option value={5}>5 days</option>
          <option value={14}>14 days</option>
        </select>
      </div>
      <button className="btn-primary" onClick={onPredict} disabled={predicting}>
        {predicting ? 'Analyzing…' : 'Run Prediction'}
      </button>
    </div>
  )
}
