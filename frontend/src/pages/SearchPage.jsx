import TickerSearch from '../components/TickerSearch'

export default function SearchPage() {
  return (
    <section className="hero">
      <div>
        <p className="eyebrow">Financial News + NLP Signals</p>
        <h2>Track sentiment in real time, then score BUY/HOLD/SELL</h2>
      </div>
      <TickerSearch />
    </section>
  )
}
