import { describe, expect, it } from 'vitest'
import * as A from './analytics'

// Expected values come from running the backend code (app/utils/*, app/services/price_data.py,
// vaderSentiment) on the same inputs; the iOS tests use the same numbers.
const bars = (base, amp, period, drift, withVolume = false) =>
  Array.from({ length: 60 }, (_, i) => {
    const close = base + amp * Math.sin(i / period) + drift * i
    return { timestamp: new Date((1_767_225_600 + i * 86_400) * 1000).toISOString(), open: close, high: close, low: close, close, volume: withVolume ? 1000 + 50 * (i % 7) : 0 }
  })

describe('analytics port', () => {
  it('stats', () => {
    const x = [0.5, -0.2, 0.1, 0.8, -0.6]
    expect(A.mean(x)).toBeCloseTo(0.12, 9)
    expect(A.std(x)).toBeCloseTo(0.5540758070878028, 9)
  })

  it('decayedMean weights by age (half-life), not by article order', () => {
    expect(A.decayedMean([{ value: 0.2, ageDays: 3 }, { value: 0.6, ageDays: 3 }], 5)).toBeCloseTo(0.4, 12) // equal ages: plain mean
    expect(A.decayedMean([{ value: 1, ageDays: 0 }, { value: 0, ageDays: 1 }], 1)).toBeCloseTo(1 / 1.5, 12) // older value counts half
    expect(A.decayedMean([{ value: 1, ageDays: -2 }, { value: 0, ageDays: 0 }], 1)).toBeCloseTo(0.5, 12)    // future timestamps clamp to age 0
    expect(A.decayedMean([], 1)).toBe(0)
    // a longer half-life lets older values count more
    const pts = [{ value: -0.6, ageDays: 0.04 }, { value: 0.8, ageDays: 4 }]
    expect(A.decayedMean(pts, 10)).toBeGreaterThan(A.decayedMean(pts, 2))
  })

  it('risk metrics match the backend', () => {
    const r = A.riskMetrics(bars(100, 10, 5, 0.1), bars(400, 20, 7, 0.3))
    expect(r.annualized_volatility).toBeCloseTo(0.21440983353406579, 9)
    expect(r.beta_to_benchmark).toBeCloseTo(-0.003717400959689276, 9)
    expect(r.max_drawdown).toBeCloseTo(-0.1663660238846164, 9)
    expect(r.high_water_mark).toBeCloseTo(113.89358246623382, 9)
    expect(r.cumulative_return).toBeCloseTo(-0.010352508477712186, 9)
    expect(A.riskMetrics(bars(100, 1, 5, 0).slice(0, 10), bars(100, 1, 5, 0).slice(0, 10)).annualized_volatility).toBe(0)
  })

  it('price features match the backend', () => {
    const f = A.priceFeatures(bars(100, 10, 5, 0.1, true))
    expect(f.rsi_14).toBeCloseTo(20.88933992202965, 6)
    expect(f.momentum_5d).toBeCloseTo(0.03529750961078859, 9)
    expect(f.bb_position).toBeCloseTo(0.356324167621198, 9)
    expect(f.volume_ratio).toBeCloseTo(1.0021786492374727, 9)
    expect(A.priceFeatures([])).toEqual({ rsi_14: 50, momentum_5d: 0, bb_position: 0.5, volume_ratio: 1 })
  })

  it('VADER matches the backend default engine', () => {
    expect(A.sentiment('Apple shares fall after regulators announce antitrust probe')).toBeCloseTo(0.296, 3)
    expect(A.sentiment('Tesla recalls 200,000 vehicles over safety defect')).toBeCloseTo(0.1027, 4)
    expect(A.sentiment('Apple beats earnings expectations as iPhone sales surge')).toBe(0)
    expect(A.label(0.06)).toBe('POSITIVE'); expect(A.label(-0.06)).toBe('NEGATIVE'); expect(A.label(0.05)).toBe('NEUTRAL')
  })

  it('dedup key, relevance and symbol normalization', () => {
    expect(A.dedupKey('Apple hits record high - Reuters')).toBe('apple hits record high')
    expect(A.dedupKey('Apple hits record high | Yahoo Finance')).toBe('apple hits record high')
    expect(A.relevance('AAPL', 'AAPL jumps on earnings', ['AAPL', 'MSFT', 'NVDA'])).toBeCloseTo(0.77, 9)
    expect(A.relevance('AAPL', 'Tech stocks rally', ['NVDA'])).toBe(0)
    expect(A.yahooSymbol('brk.b')).toBe('BRK-B')
    expect(A.relevance('BRK.B', 'Berkshire results', ['BRK-B'])).toBeCloseTo(0.45, 9)
    expect(A.sourceWeight('Reuters')).toBe(1.25); expect(A.sourceWeight('Zacks')).toBe(1)
  })

  it('prediction rule', () => {
    const rec = (s) => A.predict({ ticker: 'aapl', horizonDays: 5, signal: s, ewma1d: 0, ewma7d: 0, sentimentVolatility: 0, articleVolume24h: 0, price: A.priceFeatures([]) })
    expect(rec(0.2).recommendation).toBe('RISE'); expect(rec(-0.2).recommendation).toBe('FALL'); expect(rec(0.15).recommendation).toBe('STABLE')
    expect(rec(0).confidence).toBe(0.52); expect(rec(5).confidence).toBe(0.85)
    expect(rec(0).ticker).toBe('AAPL')
    expect(rec(0).feature_importances.__model.version).toBe('fallback_rule_v2') // PredictionCard keys off this
  })
})
