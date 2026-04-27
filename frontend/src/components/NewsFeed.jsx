import { useState } from 'react'

function relativeTime(dateStr) {
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  return `${Math.floor(hrs / 24)}d ago`
}

export default function NewsFeed({ articles, loading }) {
  const [collapsed, setCollapsed] = useState(true)

  return (
    <div className="card">
      <div className="news-header" style={{ cursor: 'pointer' }} onClick={() => setCollapsed((c) => !c)}>
        <div className="panel-label" style={{ margin: 0 }}>Live News</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
          <span className="news-count">{articles.length} articles</span>
          <span className="news-chevron" style={{ color: 'var(--muted)', fontSize: 12, fontFamily: 'JetBrains Mono, monospace', userSelect: 'none' }}>
            {collapsed ? '▸' : '▾'}
          </span>
        </div>
      </div>
      {!collapsed && articles.length === 0 && !loading && (
        <p className="muted-text">No articles yet. Subscribe to a ticker to begin.</p>
      )}
      {!collapsed && (
      <div className="news-list">
        {articles.map((a) => {
          const label = String(a.sentiment_label || '').toLowerCase()
          return (
            <article key={a.id} className="news-article">
              <a href={a.url} target="_blank" rel="noreferrer" className="news-headline">
                {a.headline}
              </a>
              <div className="news-meta">
                <span className="source-chip">{a.source || 'unknown'}</span>
                {label && <span className={`news-badge ${label}`}>{label}</span>}
                <span className="rel-score">rel {Number(a.relevance_score || 0).toFixed(2)}</span>
                <span className="time-text">{relativeTime(a.published_at)}</span>
              </div>
            </article>
          )
        })}
      </div>
      )}
    </div>
  )
}
