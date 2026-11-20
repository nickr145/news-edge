import { describe, expect, it } from 'vitest'
import { anchorTexts, semanticExposure } from './indirect'
import { profileFor } from './news'

const unit = (...v) => { const n = Math.hypot(...v); return v.map((x) => x / n) }

describe('anchorTexts', () => {
  const nvda = profileFor('NVDA', 'NVIDIA Corporation')
  it('builds anchors for the five indirect channels from the profile, at most two per channel', () => {
    const a = anchorTexts(nvda)
    const channels = ['competitor', 'macro', 'people', 'sector', 'supply']
    expect([...new Set(a.map((x) => x.channel))].sort()).toEqual(channels)
    for (const ch of channels) expect(a.filter((x) => x.channel === ch).length).toBeLessThanOrEqual(2)
    expect(a.find((x) => x.channel === 'supply').text).toContain('tsmc')
    expect(a.find((x) => x.channel === 'supply').text).toContain('nvidia')
  })
  it('drops a term contained in a longer one and repeated terms ("huang" in "jensen huang", "tsmc" twice)', () => {
    const a = anchorTexts(nvda)
    const people = a.filter((x) => x.channel === 'people').map((x) => x.text).join(' ')
    expect(people).toContain('jensen huang')
    expect(people).not.toContain('huang, ')
    const supply = a.filter((x) => x.channel === 'supply').map((x) => x.text).join(' ')
    expect(supply.match(/tsmc/g)).toHaveLength(1)
  })
  it('gives a ticker with no profile no anchors', () => {
    expect(anchorTexts(profileFor('ZZZZ'))).toEqual([])
  })
})

describe('semanticExposure', () => {
  const anchors = [
    { channel: 'supply', vec: unit(1, 0, 0, 0) },
    { channel: 'sector', vec: unit(0, 1, 0, 0) },
    { channel: 'macro', vec: unit(0, 0, 1, 0) },
    { channel: 'competitor', vec: unit(0, 0, 0, 1) }
  ]
  const opts = { threshold: 0.6, margin: 0.2 }

  it("admits a headline close to one channel, with that channel's relevance, weight and sign", () => {
    const r = semanticExposure(unit(1, 0.1, 0, 0), anchors, opts)
    expect(r.admit).toBe(true)
    expect(r.exposure).toEqual({ channel: 'supply', relevance: 0.5, weight: 0.5, sign: 1, embedded: true })
    expect(r.cosine).toBeCloseTo(0.995, 3)
  })
  it('does not admit below the threshold', () => {
    const r = semanticExposure(unit(1, 1, 1, 1), anchors, opts) // cosine 0.5 to every channel
    expect(r.admit).toBe(false)
  })
  it('does not admit an ambiguous headline whose best channel barely beats the runner-up', () => {
    const r = semanticExposure(unit(1, 0.9, 0, 0), anchors, opts) // supply 0.743, sector 0.669
    expect(r.channel).toBe('supply')
    expect(r.cosine).toBeGreaterThanOrEqual(opts.threshold)
    expect(r.margin).toBeCloseTo(0.074, 2)
    expect(r.admit).toBe(false)
  })
  it('scores a channel by its best anchor and keeps the competitor sign negative', () => {
    const two = [...anchors, { channel: 'competitor', vec: unit(0, 0, 0.5, 1) }]
    const r = semanticExposure(unit(0, 0, 0.5, 1), two, opts)
    expect(r.channel).toBe('competitor')
    expect(r.cosine).toBeCloseTo(1, 5)
    expect(r.exposure.sign).toBe(-1)
    expect(r.exposure.relevance).toBe(0.3)
  })
  it('returns null without anchors', () => {
    expect(semanticExposure(unit(1, 0, 0, 0), [], opts)).toBeNull()
  })
})
