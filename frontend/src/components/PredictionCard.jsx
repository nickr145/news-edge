export default function PredictionCard({ prediction, onPredict }) {
  return (
    <section className="card">
      <div className="row between">
        <h2>Recommendation</h2>
        <button onClick={onPredict}>Run Prediction</button>
      </div>
      {!prediction && <p>No prediction yet.</p>}
      {prediction && (
        <div className="stack">
          <p className={`signal ${prediction.recommendation?.toLowerCase()}`}>{prediction.recommendation}</p>
          <p>Confidence: {(prediction.confidence * 100).toFixed(1)}%</p>
          <p>RSI: {prediction.price_rsi?.toFixed?.(2)}</p>
        </div>
      )}
    </section>
  )
}
