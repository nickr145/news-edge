import { useId, useState } from 'react'

function relativeTime(dateStr) {
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  return `${Math.floor(hrs / 24)}d ago`
}

// Why a headline counts for this ticker when it doesn't name the company (see lib/local/news.js).
const CHANNEL_LABELS = { people: 'Leadership', supply: 'Supply chain', sector: 'Sector', competitor: 'Competitor', macro: 'Macro' }

const PAGE = 25

export default function NewsFeed({ articles, loading }) {
  const [open, setOpen] = useState(true)
  const [shown, setShown] = useState(PAGE)
  const listId = useId()

  return (
    <section className="card">
      <button className="news-toggle" onClick={() => setOpen((o) => !o)} aria-expanded={open} aria-controls={listId}>
        <h2 className="card-title">Live news</h2>
        <span className="news-count">{articles.length} articles {open ? '▾' : '▸'}</span>
      </button>

      <div id={listId} hidden={!open}>
        {articles.length === 0 && !loading && (
          <p className="muted-text" style={{ marginTop: '0.8rem' }}>No articles yet for this window. Try a longer window or a lower relevance.</p>
        )}
        <ul className="news-list">
          {articles.slice(0, shown).map((a) => {
            const label = String(a.sentiment_label || '').toLowerCase()
            return (
              <li key={a.id} className="news-row">
                <time className="news-time" dateTime={a.published_at}>{relativeTime(a.published_at)}</time>
                <div>
                  <a href={a.url} target="_blank" rel="noreferrer" className="news-headline">{a.headline}</a>
                  <div className="news-meta">
                    <span>{a.source || 'unknown'}</span>
                    {CHANNEL_LABELS[a.channel] && <span className="why" title="Indirect news: it bears on this ticker without naming it">{CHANNEL_LABELS[a.channel]}</span>}
                    {a.story_damp < 1 && <span title={`Part of an ongoing story ("${a.storyline}"), piece #${a.story_rank}: later pieces of a story count for less`}>ongoing story, counts {Math.round(a.story_damp * 100)}%</span>}
                    {a.event_outlets > 1 && <span title="Counted once; this story was reported by several outlets">+{a.event_outlets - 1} outlet{a.event_outlets > 2 ? 's' : ''}</span>}
                  </div>
                </div>
                <div className="news-side">
                  {label && <span className={`tag ${label}`}>{label}</span>}
                  <span>rel {Number(a.relevance_score || 0).toFixed(2)}</span>
                </div>
              </li>
            )
          })}
        </ul>
        {articles.length > shown && (
          <button className="btn news-more" onClick={() => setShown((n) => n + PAGE)}>
            Show {Math.min(PAGE, articles.length - shown)} more
          </button>
        )}
      </div>
    </section>
  )
}
