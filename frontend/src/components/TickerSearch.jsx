import { useEffect, useId, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { TICKERS } from '../data/tickers'

export default function TickerSearch({ compact = false }) {
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [activeIdx, setActiveIdx] = useState(0)
  const navigate = useNavigate()
  const wrapperRef = useRef(null)
  const inputRef = useRef(null)
  const listId = useId()

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

  // "/" jumps to search from anywhere that isn't a text field.
  useEffect(() => {
    const onSlash = (e) => {
      const tag = document.activeElement?.tagName
      if (e.key !== '/' || e.metaKey || e.ctrlKey || tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
      e.preventDefault()
      inputRef.current?.focus()
    }
    document.addEventListener('keydown', onSlash)
    return () => document.removeEventListener('keydown', onSlash)
  }, [])

  useEffect(() => {
    const handler = (e) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const expanded = open && matches.length > 0

  return (
    <div className={`search${compact ? ' search--compact' : ''}`} ref={wrapperRef}>
      <input
        ref={inputRef}
        className="search-input"
        role="combobox"
        aria-label="Search ticker or company"
        aria-expanded={expanded}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={expanded ? `${listId}-${activeIdx}` : undefined}
        value={query}
        onChange={(e) => {
          setQuery(e.target.value)
          setOpen(true)
          setActiveIdx(0)
        }}
        onFocus={() => { if (query) setOpen(true) }}
        onKeyDown={onKeyDown}
        placeholder={compact ? 'Search ticker or company' : 'Search a ticker or company: NVDA, Apple, Amazon'}
        autoFocus={!compact}
        autoComplete="off"
        spellCheck={false}
      />
      {!query && <kbd className="search-kbd" aria-hidden="true">/</kbd>}
      {expanded && (
        <ul className="search-menu" id={listId} role="listbox">
          {matches.map((t, i) => (
            <li
              key={t.symbol}
              id={`${listId}-${i}`}
              role="option"
              aria-selected={i === activeIdx}
              className="search-option"
              onMouseDown={() => go(t.symbol)}
              onMouseEnter={() => setActiveIdx(i)}
            >
              <span className="search-option-symbol">{t.symbol}</span>
              <span className="search-option-name">{t.name}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
