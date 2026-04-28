import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'

function WatchlistCard({ ticker, onRemove }) {
  const [summary, setSummary] = useState(null)

  useEffect(() => {
    api.get(`/api/news/${ticker}/sentiment`, { params: { days: 7 } })
      .then((r) => setSummary(r.data))
      .catch(() => {})
  }, [ticker])

  const ewma = summary?.ewma_compound
  const sentClass = ewma == null ? '' : ewma > 0.05 ? 'positive' : ewma < -0.05 ? 'danger' : ''

  return (
    <div className="watchlist-card">
      <div className="watchlist-card-top">
        <Link to={`/ticker/${ticker}`} className="watchlist-ticker">{ticker}</Link>
        <button className="watchlist-remove" onClick={() => onRemove(ticker)} title="Remove from watchlist">×</button>
      </div>
      <div className="watchlist-stats">
        <div className="metric-cell">
          <span className="metric-label">EWMA</span>
          <span className={`metric-value ${sentClass}`}>
            {ewma != null ? Number(ewma).toFixed(3) : '—'}
          </span>
        </div>
        <div className="metric-cell">
          <span className="metric-label">Articles</span>
          <span className="metric-value">{summary?.count ?? '—'}</span>
        </div>
      </div>
    </div>
  )
}

export default function WatchlistPanel({ watchlist, onRemove }) {
  if (!watchlist.length) return null

  return (
    <div className="watchlist-section">
      <div className="watchlist-header">Watchlist</div>
      <div className="watchlist-grid">
        {watchlist.map((ticker) => (
          <WatchlistCard key={ticker} ticker={ticker} onRemove={onRemove} />
        ))}
      </div>
    </div>
  )
}
