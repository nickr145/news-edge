export default function PredictionCard({ prediction, onPredict, predicting }) {
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
        </>
      ) : (
        <p className="muted-text" style={{ marginBottom: '0.75rem' }}>Run a prediction to see a BUY / HOLD / SELL signal.</p>
      )}
      <button className="btn-primary" onClick={onPredict} disabled={predicting}>
        {predicting ? 'Analyzing…' : 'Run Prediction'}
      </button>
    </div>
  )
}
