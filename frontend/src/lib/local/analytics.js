// Browser port of the backend's pure computation (app/utils/*, app/services/{analytics,price_data,prediction}.py),
// itself mirrored by ios/NewsEdge/Shared/Analytics.swift. Keep numerically in step with them
// (sample std/cov, EWMA alpha 0.3). Sentiment is VADER, the backend's default engine.
import vader from 'vader-sentiment'

export const mean = (v) => (v.length ? v.reduce((a, b) => a + b, 0) / v.length : 0)

export function std(v) {
  if (v.length < 2) return 0
  const m = mean(v)
  return Math.sqrt(v.reduce((a, x) => a + (x - m) ** 2, 0) / (v.length - 1))
}

export function ewma(v, alpha = 0.3) {
  if (!v.length) return 0
  let acc = v[0]
  for (const x of v.slice(1)) acc = alpha * x + (1 - alpha) * acc
  return acc
}

export const sentiment = (text) => vader.SentimentIntensityAnalyzer.polarity_scores(text || '').compound
export const label = (c) => (c > 0.05 ? 'POSITIVE' : c < -0.05 ? 'NEGATIVE' : 'NEUTRAL')

export const normalize = (t) => String(t || '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
export const dedupKey = (headline) => normalize(String(headline || '').replace(/\s*[-–|]\s*[A-Za-z][\w\s.&]{1,40}$/, '').trim())

const SOURCE_WEIGHTS = { reuters: 1.25, bloomberg: 1.25, cnbc: 1.1, benzinga: 0.95 }
export const sourceWeight = (source) => SOURCE_WEIGHTS[normalize(source)] ?? 1.0

/** Yahoo writes share classes with a dash (BRK-B); users and the catalog use BRK.B. */
export const yahooSymbol = (t) => String(t || '').trim().toUpperCase().replace(/\./g, '-')

export function relevance(ticker, headline, symbols = []) {
  const t = String(ticker).toLowerCase()
  const h = String(headline || '').toLowerCase()
  const syms = symbols.map(yahooSymbol)
  let score = 0
  if (syms.includes(yahooSymbol(ticker))) score += 0.45
  if (h.includes(t)) score += 0.35
  if (syms.length) score -= Math.min(0.25, 0.04 * Math.max(syms.length - 1, 0))
  if (h.includes(t)) score += 0.05
  return Math.max(0, Math.min(1, score))
}

const dayKey = (ts) => Math.floor(Date.parse(ts) / 86_400_000)

export function riskMetrics(bars, benchmark) {
  const zero = { annualized_volatility: 0, beta_to_benchmark: 0, max_drawdown: 0, high_water_mark: 0, cumulative_return: 0 }
  if (bars.length < 30 || benchmark.length < 30) return zero
  const returns = (b) => b.slice(1).map((x, i) => ({ day: dayKey(x.timestamp), r: x.close / b[i].close - 1 }))
  const benchByDay = new Map(returns(benchmark).map((x) => [x.day, x.r]))
  const merged = returns(bars).filter((x) => benchByDay.has(x.day)).map((x) => [x.r, benchByDay.get(x.day)])
  if (merged.length < 2) return zero

  const r = merged.map((m) => m[0]), b = merged.map((m) => m[1])
  const mr = mean(r), mb = mean(b)
  const cov = r.reduce((a, x, i) => a + (x - mr) * (b[i] - mb), 0) / (r.length - 1)
  const varB = std(b) ** 2

  const closes = bars.map((x) => x.close)
  let runMax = -Infinity, maxDD = 0
  for (const c of closes) {
    runMax = Math.max(runMax, c)
    maxDD = Math.min(maxDD, c / runMax - 1)
  }
  return {
    annualized_volatility: std(r) * Math.sqrt(252),
    beta_to_benchmark: varB > 0 ? cov / varB : 0,
    max_drawdown: maxDD,
    high_water_mark: runMax,
    cumulative_return: closes[0] !== 0 ? closes[closes.length - 1] / closes[0] - 1 : 0
  }
}

export function priceFeatures(bars) {
  const d = { rsi_14: 50, momentum_5d: 0, bb_position: 0.5, volume_ratio: 1 }
  if (bars.length < 30) return d
  const close = bars.map((b) => b.close), volume = bars.map((b) => b.volume)
  const n = close.length

  const deltas = close.slice(1).map((c, i) => c - close[i]).slice(-14)
  const gain = deltas.reduce((a, x) => a + Math.max(x, 0), 0) / 14
  let loss = deltas.reduce((a, x) => a + Math.max(-x, 0), 0) / 14
  if (loss === 0) loss = 1e-9
  const rsi = 100 - 100 / (1 + gain / loss)

  const win = close.slice(-20)
  const ma = mean(win), sd = std(win)
  const lower = ma - 2 * sd, upper = ma + 2 * sd
  const width = upper - lower === 0 ? 1e-9 : upper - lower
  const bb = Math.max(0, Math.min(1, (close[n - 1] - lower) / width))

  const avgVol = mean(volume.slice(-20))
  return {
    rsi_14: rsi,
    momentum_5d: close[n - 1] / close[n - 6] - 1,
    bb_position: bb,
    volume_ratio: volume[n - 1] / (avgVol === 0 ? 1e-9 : avgVol)
  }
}

/** The backend's fallback rule (no trained model exists in production either). */
export function predict({ ticker, horizonDays, ewma1d, ewma7d, sentimentVolatility, articleVolume24h, price, now = new Date() }) {
  return {
    id: Math.floor(now.getTime() / 1000),
    ticker: String(ticker).toUpperCase(),
    predicted_at: now.toISOString(),
    recommendation: ewma1d > 0.15 ? 'RISE' : ewma1d < -0.15 ? 'FALL' : 'STABLE',
    confidence: Math.min(0.85, 0.52 + Math.abs(ewma1d) * 0.35),
    sentiment_score: ewma1d,
    price_rsi: price.rsi_14,
    feature_importances: {
      ewma_sentiment_1d: ewma1d,
      ewma_sentiment_7d: ewma7d,
      sentiment_volatility: sentimentVolatility,
      article_volume_24h: articleVolume24h,
      rsi_14: price.rsi_14,
      momentum_5d: price.momentum_5d,
      bb_position: price.bb_position,
      volume_ratio: price.volume_ratio,
      __model: { version: 'fallback_rule_v2', reason: 'on_device_rule' }
    },
    horizon_days: horizonDays
  }
}
