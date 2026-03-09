export default function NewsFeed({ articles }) {
  return (
    <section className="card">
      <h2>Live News</h2>
      <div className="stack">
        {articles.length === 0 && <p>No articles yet.</p>}
        {articles.map((a) => (
          <article key={a.id} className="news-item">
            <a href={a.url} target="_blank" rel="noreferrer">{a.headline}</a>
            <p>{a.summary || 'No summary available'}</p>
            <div className="meta-row">
              <span>{a.source || 'Unknown'}</span>
              <span className={`badge ${String(a.sentiment_label || '').toLowerCase()}`}>{a.sentiment_label || 'N/A'}</span>
              <span>Rel {Number(a.relevance_score || 0).toFixed(2)}</span>
              <span>{new Date(a.published_at).toLocaleString()}</span>
            </div>
          </article>
        ))}
      </div>
    </section>
  )
}
