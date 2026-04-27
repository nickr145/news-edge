import TickerSearch from '../components/TickerSearch'

export default function SearchPage() {
  return (
    <div className="search-hero">
      <div className="hero-logotype">
        <div className="hero-mark">NE</div>
        <h1 className="hero-title">NewsEdge</h1>
        <p className="hero-sub">Financial news intelligence — sentiment signals, risk metrics, and ML-powered recommendations.</p>
      </div>
      <TickerSearch />
    </div>
  )
}
