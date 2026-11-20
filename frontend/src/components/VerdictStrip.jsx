import { signed, usd } from '../lib/format'

const DIRECTION = {
  rise: { word: 'Rise', arrow: '▲' },
  buy: { word: 'Rise', arrow: '▲' },
  fall: { word: 'Fall', arrow: '▼' },
  sell: { word: 'Fall', arrow: '▼' },
  stable: { word: 'Stable', arrow: '–' },
  hold: { word: 'Stable', arrow: '–' },
}
const CLASS = { rise: 'rise', buy: 'rise', fall: 'fall', sell: 'fall', stable: 'stable', hold: 'stable' }

/** Top of the stock page: who it is, where it trades, and what the model expects, on one line. */
export default function VerdictStrip({ ticker, companyName, quote, prediction, predicting }) {
  const key = prediction?.recommendation?.toLowerCase()
  const dir = DIRECTION[key]
  const tone = CLASS[key] || ''
  const confidence = prediction ? Math.max(0, Math.min(1, Number(prediction.confidence) || 0)) : 0
  const up = quote?.change > 0
  const down = quote?.change < 0

  return (
    <section className="verdict" aria-label={`${ticker} summary`}>
      <div className="verdict-id">
        <h1 className="verdict-symbol">{ticker}</h1>
        {companyName && <div className="verdict-name">{companyName}</div>}
      </div>

      <div className="verdict-quote">
        {quote ? (
          <>
            <span className="verdict-price">{usd(quote.price)}</span>
            {quote.change != null && (
              <span className={`verdict-change ${up ? 'up' : down ? 'down' : 'flat'}`}>
                {up ? '▲' : down ? '▼' : ''} {signed(quote.change)} ({signed(quote.pct)}%)
              </span>
            )}
            <span className="verdict-note">Last daily close</span>
          </>
        ) : (
          <span className="verdict-note">No price data</span>
        )}
      </div>

      <div className="verdict-signal" aria-live="polite">
        {dir ? (
          <>
            <div className="verdict-call">
              <span className={`verdict-word ${tone}`}>{dir.word} {dir.arrow}</span>
              <span className="verdict-conf"><b>{(confidence * 100).toFixed(0)}%</b> confidence · {prediction.horizonDays}-day</span>
            </div>
            <div className="meter" role="img" aria-label={`Confidence ${(confidence * 100).toFixed(0)} percent`}>
              <div className={`meter-fill ${tone}`} style={{ transform: `scaleX(${confidence})` }} />
            </div>
          </>
        ) : (
          <span className="verdict-pending">{predicting ? 'Calculating the signal…' : 'No signal yet. Run a prediction.'}</span>
        )}
      </div>
    </section>
  )
}
