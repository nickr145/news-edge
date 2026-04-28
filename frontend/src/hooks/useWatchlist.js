import { useEffect, useState } from 'react'

const KEY = 'newsedge_watchlist'

export function useWatchlist() {
  const [watchlist, setWatchlist] = useState(() => {
    try { return JSON.parse(localStorage.getItem(KEY) || '[]') }
    catch { return [] }
  })

  useEffect(() => {
    localStorage.setItem(KEY, JSON.stringify(watchlist))
  }, [watchlist])

  const add = (ticker) => setWatchlist((prev) => (prev.includes(ticker) ? prev : [...prev, ticker]))
  const remove = (ticker) => setWatchlist((prev) => prev.filter((t) => t !== ticker))
  const toggle = (ticker) => setWatchlist((prev) =>
    prev.includes(ticker) ? prev.filter((t) => t !== ticker) : [...prev, ticker]
  )
  const isWatched = (ticker) => watchlist.includes(ticker)

  return { watchlist, add, remove, toggle, isWatched }
}
