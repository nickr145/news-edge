import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'

function WatchlistCard({ ticker, onRemove }) {
  const [summary, setSummary] = useState(null)
  const navigate = useNavigate()

  useEffect(() => {
    api.get(`/api/news/${ticker}/sentiment`, { params: { days: 7 } })
      .then((r) => setSummary(r.data))
      .catch(() => {})
  }, [ticker])

  const ewma = summary?.ewma_compound
  const sentClass = ewma == null ? '' : ewma > 0.05 ? 'positive' : ewma < -0.05 ? 'danger' : ''

  const handleRemove = (e) => {
    e.stopPropagation()
    onRemove(ticker)
  }

  return (
    <div
      className="watchlist-card"
      role="link"
      tabIndex={0}
      onClick={() => navigate(`/ticker/${ticker}`)}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') navigate(`/ticker/${ticker}`) }}
    >
      <div className="watchlist-card-top">
        <span className="watchlist-ticker">{ticker}</span>
        <div className="watchlist-card-actions">
          <button className="watchlist-remove" onClick={handleRemove} title="Remove from watchlist">×</button>
          <span className="watchlist-chevron" aria-hidden="true">›</span>
        </div>
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
