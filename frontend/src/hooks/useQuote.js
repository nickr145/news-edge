import { useEffect, useState } from 'react'
import { api } from '../lib/api'
import { quoteFromBars } from '../lib/format'

/** Latest close, 1-day change and recent closes for a ticker (null until loaded or if unavailable). */
export function useQuote(ticker, limit = 30) {
  const [quote, setQuote] = useState(null)
  useEffect(() => {
    let live = true
    setQuote(null)
    api.get(`/api/price/${ticker}/bars`, { params: { limit } })
      .then((r) => { if (live) setQuote(quoteFromBars(r.data)) })
      .catch(() => {})
    return () => { live = false }
  }, [ticker, limit])
  return quote
}
