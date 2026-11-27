const ITEMS = [
  {
    title: 'News that never names the company',
    body: 'A supplier, a competitor or a CEO in the headlines still moves a stock. These are matched and tagged with why they count.',
  },
  {
    title: 'One story, counted once',
    body: 'The same event from several outlets is a single data point, and follow-ups to a running story count for less.',
  },
  {
    title: 'A signal that shows its work',
    body: 'Each stock gets a Rise, Stable or Fall call for 1, 5 or 14 days, with the inputs that pushed it there.',
  },
]

export default function HowItReads() {
  return (
    <aside className="reads" aria-label="How NewsEdge reads the news">
      <h2 className="watchlist-title">How it reads the news</h2>
      {ITEMS.map((i) => (
        <div key={i.title} className="reads-item">
          <h3>{i.title}</h3>
          <p>{i.body}</p>
        </div>
      ))}
    </aside>
  )
}
