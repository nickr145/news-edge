/** '+1.23' / '−1.23' / '0.00'. A real minus sign, so direction never depends on colour alone. */
export const signed = (n, digits = 2) =>
  `${n > 0 ? '+' : n < 0 ? '−' : ''}${Math.abs(n).toFixed(digits)}`

export const usd = (n) => `$${Number(n).toFixed(2)}`

/** Latest daily close and its change vs the close before it, from price bars. */
export function quoteFromBars(bars) {
  const closes = (bars || []).map((b) => Number(b.close)).filter(Number.isFinite)
  if (!closes.length) return null
  const price = closes[closes.length - 1]
  const prev = closes.length > 1 ? closes[closes.length - 2] : null
  return {
    price,
    change: prev == null ? null : price - prev,
    pct: prev == null || prev === 0 ? null : ((price - prev) / prev) * 100,
    closes,
  }
}
