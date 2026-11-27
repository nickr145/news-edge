import { Link } from 'react-router-dom'
import { TICKERS } from '../data/tickers'
import { useQuote } from '../hooks/useQuote'
import { signed, usd } from '../lib/format'
import Sparkline from './Sparkline'

const POPULAR = ['NVDA', 'AAPL', 'MSFT', 'AMZN', 'GOOGL', 'META', 'TSLA', 'AVGO']

function Row({ ticker, watched, onToggle }) {
  const q = useQuote(ticker)
  const tone = q?.pct > 0 ? 'up' : q?.pct < 0 ? 'down' : 'flat'
  const name = TICKERS.find((t) => t.symbol === ticker)?.name
  return (
    <tr>
      <td>
        <Link className="wl-symbol" to={`/ticker/${ticker}`}>{ticker}</Link>
        {name && <span className="wl-name">{name}</span>}
      </td>
      <td>{q ? usd(q.price) : '–'}</td>
      <td className={q?.pct != null ? tone : 'flat'}>{q?.pct != null ? `${signed(q.pct)}%` : '–'}</td>
      <td className="col-spark"><Sparkline closes={q?.closes} /></td>
      <td>
        <button className="btn btn--small" aria-pressed={watched} onClick={() => onToggle(ticker)}>
          {watched ? 'Watching' : '+ Watch'}
        </button>
      </td>
    </tr>
  )
}

export default function PopularPanel({ watchlist, onToggle }) {
  return (
    <section className="watchlist">
      <h2 className="watchlist-title">Popular</h2>
      <table className="wl-table wl-table--plain">
        <thead>
          <tr>
            <th scope="col">Ticker</th>
            <th scope="col">Last</th>
            <th scope="col">1D</th>
            <th scope="col" className="col-spark">30D</th>
            <th scope="col"><span className="sr-only">Watch</span></th>
          </tr>
        </thead>
        <tbody>
          {POPULAR.map((t) => <Row key={t} ticker={t} watched={watchlist.includes(t)} onToggle={onToggle} />)}
        </tbody>
      </table>
    </section>
  )
}
