import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { TICKERS } from '../data/tickers'
import { useQuote } from '../hooks/useQuote'
import { api } from '../lib/api'
import { signed, usd } from '../lib/format'
import Sparkline from './Sparkline'

const EXAMPLES = ['NVDA', 'AAPL', 'MSFT', 'TSLA']
function WatchRow({ ticker, onRemove }) {
  const [summary, setSummary] = useState(null)
  const quote = useQuote(ticker)

  useEffect(() => {
    api.get(`/api/news/${ticker}/sentiment`, { params: { days: 7 } })
      .then((r) => setSummary(r.data)).catch(() => {})
  }, [ticker])

  const name = TICKERS.find((t) => t.symbol === ticker)?.name
  const ewma = summary?.ewma_compound
  const tone = (n) => (n > 0 ? 'up' : n < 0 ? 'down' : 'flat')
  const sentTone = ewma == null || Math.abs(ewma) <= 0.05 ? 'flat' : tone(ewma)

  return (
    <tr>
      <td>
        <Link className="wl-symbol" to={`/ticker/${ticker}`}>{ticker}</Link>
        {name && <span className="wl-name">{name}</span>}
      </td>
      <td>{quote ? usd(quote.price) : '–'}</td>
      <td className={quote?.pct != null ? tone(quote.pct) : 'flat'}>
        {quote?.pct != null ? `${signed(quote.pct)}%` : '–'}
      </td>
      <td className="col-spark"><Sparkline closes={quote?.closes} /></td>
      <td className={sentTone}>{ewma != null ? signed(Number(ewma), 3) : '–'}</td>
      <td className="col-articles">{summary?.count ?? '–'}</td>
      <td>
        <button className="wl-remove" onClick={() => onRemove(ticker)} aria-label={`Remove ${ticker} from watchlist`}>×</button>
      </td>
    </tr>
  )
}

export default function WatchlistPanel({ watchlist, onRemove }) {
  if (!watchlist.length) {
    return (
      <section className="watchlist">
        <h2 className="watchlist-title">Watchlist</h2>
        <p className="empty-hint">
          Nothing here yet. Open a stock and choose Watch to track it. Try{' '}
          {EXAMPLES.map((t) => <Link key={t} to={`/ticker/${t}`}>{t}</Link>)}
        </p>
      </section>
    )
  }

  return (
    <section className="watchlist">
      <h2 className="watchlist-title">Watchlist</h2>
      <table className="wl-table">
        <thead>
          <tr>
            <th scope="col">Ticker</th>
            <th scope="col">Last</th>
            <th scope="col">1D</th>
            <th scope="col" className="col-spark">30D</th>
            <th scope="col" title="7-day news sentiment, EWMA">Sentiment</th>
            <th scope="col" className="col-articles">Stories</th>
            <th scope="col"><span className="sr-only">Remove</span></th>
          </tr>
        </thead>
        <tbody>
          {watchlist.map((t) => <WatchRow key={t} ticker={t} onRemove={onRemove} />)}
        </tbody>
      </table>
    </section>
  )
}
