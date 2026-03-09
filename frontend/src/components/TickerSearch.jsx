import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

export default function TickerSearch() {
  const [symbol, setSymbol] = useState('NVDA')
  const navigate = useNavigate()

  const onSubmit = (e) => {
    e.preventDefault()
    const cleaned = symbol.trim().toUpperCase()
    if (!cleaned) return
    navigate(`/ticker/${cleaned}`)
  }

  return (
    <form className="card search-card" onSubmit={onSubmit}>
      <label htmlFor="symbol">Ticker</label>
      <div className="row">
        <input
          id="symbol"
          value={symbol}
          onChange={(e) => setSymbol(e.target.value)}
          placeholder="AAPL"
          maxLength={10}
        />
        <button type="submit">Open Dashboard</button>
      </div>
    </form>
  )
}
