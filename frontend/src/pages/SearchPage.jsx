import TickerSearch from '../components/TickerSearch'
import WatchlistPanel from '../components/WatchlistPanel'
import { useWatchlist } from '../hooks/useWatchlist'

export default function SearchPage() {
  const { watchlist, remove } = useWatchlist()

  return (
    <div className="search-hero">
      <div className="hero-logotype">
        <div className="hero-mark">NE</div>
        <h1 className="hero-title">NewsEdge</h1>
        <p className="hero-sub">Financial news intelligence — sentiment signals, risk metrics, and ML-powered recommendations.</p>
      </div>
      <TickerSearch />
      <WatchlistPanel watchlist={watchlist} onRemove={remove} />
    </div>
  )
}
