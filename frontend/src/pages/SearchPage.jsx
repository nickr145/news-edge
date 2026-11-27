import HowItReads from '../components/HowItReads'
import MarketStrip from '../components/MarketStrip'
import PopularPanel from '../components/PopularPanel'
import TickerSearch from '../components/TickerSearch'
import WatchlistPanel from '../components/WatchlistPanel'
import { useWatchlist } from '../hooks/useWatchlist'

export default function SearchPage() {
  const { watchlist, remove, toggle } = useWatchlist()

  return (
    <main className="home">
      <header className="home-head">
        <h1 className="home-title">Find a ticker</h1>
        <p className="home-sub">News sentiment, risk metrics and a short-horizon signal for the stocks you follow.</p>
        <TickerSearch />
      </header>

      <MarketStrip />

      <div className="home-grid">
        <div className="home-main">
          <WatchlistPanel watchlist={watchlist} onRemove={remove} />
          <PopularPanel watchlist={watchlist} onToggle={toggle} />
        </div>
        <HowItReads />
      </div>
    </main>
  )
}
