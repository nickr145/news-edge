import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { TICKERS } from '../data/tickers'

export default function TickerSearch() {
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [activeIdx, setActiveIdx] = useState(0)
  const navigate = useNavigate()
  const wrapperRef = useRef(null)

  const q = query.trim().toUpperCase()
  const words = q.split(/\s+/).filter(Boolean)

  const rank = (t) => {
    const sym = t.symbol
    const name = t.name.toUpperCase()
    if (sym === q) return 0
    if (sym.startsWith(q)) return 1
    if (name.startsWith(q)) return 2
    if (words.length > 1 && words.every((w) => name.includes(w))) return 3
    if (name.includes(q)) return 4
    return 5
  }

  const matches = q.length === 0 ? [] : TICKERS
    .filter((t) => {
      const sym = t.symbol
      const name = t.name.toUpperCase()
      return (
        sym.startsWith(q) ||
        name.startsWith(q) ||
        name.includes(q) ||
        (words.length > 1 && words.every((w) => name.includes(w)))
      )
    })
    .sort((a, b) => rank(a) - rank(b) || a.symbol.localeCompare(b.symbol))
    .slice(0, 8)

  const go = (symbol) => {
    navigate(`/ticker/${symbol.toUpperCase()}`)
    setQuery('')
    setOpen(false)
  }

  const onKeyDown = (e) => {
    if (!open || !matches.length) {
      if (e.key === 'Enter' && q) go(q)
      return
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActiveIdx((i) => Math.min(i + 1, matches.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActiveIdx((i) => Math.max(i - 1, 0))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      go(matches[activeIdx].symbol)
    } else if (e.key === 'Escape') {
      setOpen(false)
    }
  }

  useEffect(() => {
    const handler = (e) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  return (
    <div className="ticker-search-wrap" ref={wrapperRef}>
      <input
        className="ticker-search-input"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value)
          setOpen(true)
          setActiveIdx(0)
        }}
        onFocus={() => { if (query) setOpen(true) }}
        onKeyDown={onKeyDown}
        placeholder="Search ticker or company — AAPL, Amazon, NVDA…"
        autoFocus
        autoComplete="off"
        spellCheck={false}
      />
      {open && matches.length > 0 && (
        <div className="ticker-dropdown">
          {matches.map((t, i) => (
            <div
              key={t.symbol}
              className={`ticker-dropdown-item ${i === activeIdx ? 'active' : ''}`}
              onMouseDown={() => go(t.symbol)}
              onMouseEnter={() => setActiveIdx(i)}
            >
              <span className="ticker-dropdown-symbol">{t.symbol}</span>
              <span className="ticker-dropdown-name">{t.name}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
