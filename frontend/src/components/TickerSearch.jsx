import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

export default function TickerSearch() {
  const [symbol, setSymbol] = useState('')
  const navigate = useNavigate()

  const onSubmit = (e) => {
    e.preventDefault()
    const cleaned = symbol.trim().toUpperCase()
    if (!cleaned) return
    navigate(`/ticker/${cleaned}`)
  }

  return (
    <form className="search-form" onSubmit={onSubmit}>
      <div className="search-input-row">
        <input
          className="search-input"
          value={symbol}
          onChange={(e) => setSymbol(e.target.value)}
          placeholder="AAPL"
          maxLength={10}
          autoFocus
        />
        <button type="submit" className="btn-open">Open</button>
      </div>
      <span className="search-hint">Try AAPL · NVDA · TSLA · MSFT · AMZN</span>
    </form>
  )
}
