import { Link } from 'react-router-dom'
import { useQuote } from '../hooks/useQuote'
import { signed, usd } from '../lib/format'
import Sparkline from './Sparkline'

// Index ETFs: the app prices any ticker, so the broad market is just four more symbols.
const INDEXES = [
  { symbol: 'SPY', name: 'S&P 500' },
  { symbol: 'QQQ', name: 'Nasdaq 100' },
  { symbol: 'DIA', name: 'Dow Jones' },
  { symbol: 'IWM', name: 'Russell 2000' },
]

function Cell({ symbol, name }) {
  const q = useQuote(symbol)
  const tone = q?.pct > 0 ? 'up' : q?.pct < 0 ? 'down' : 'flat'
  return (
    <li>
      <Link className="market-cell" to={`/ticker/${symbol}`}>
        <span className="market-name">{name} <span className="market-sym">{symbol}</span></span>
        <span className="market-row">
          <span className="market-price">{q ? usd(q.price) : '–'}</span>
          <span className={`market-change ${tone}`}>{q?.pct != null ? `${q.pct > 0 ? '▲' : q.pct < 0 ? '▼' : ''} ${signed(q.pct)}%` : ''}</span>
        </span>
        <Sparkline closes={q?.closes} width={120} height={28} />
      </Link>
    </li>
  )
}

export default function MarketStrip() {
  return (
    <section aria-label="Market overview">
      <ul className="market">
        {INDEXES.map((i) => <Cell key={i.symbol} {...i} />)}
      </ul>
    </section>
  )
}
