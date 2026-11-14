import { describe, expect, it } from 'vitest'
import { entitiesOf, entitySimilarity, pairScore, semanticMerges, timeSimilarity } from './semantic'
import { groupEvents } from './news'
import { quantize } from './embeddings'

const H = 3_600_000
const WINDOW = 48 * H
const unit = (...v) => { const n = Math.hypot(...v); return v.map((x) => x / n) }
/** An item as groupEvents/semanticMerges see it. `vec` is a small direction; embedded through the real int8 codec. */
const item = (id, headline, hours, vec, extra = {}) => ({
  article: { id, headline, source: `src${id}`, emb: vec ? quantize(vec) : undefined },
  exposure: { weight: 1, relevance: 0.9, channel: 'direct', sign: 1 }, tMs: hours * H, value: 0.1, ...extra
})

describe('timeSimilarity', () => {
  it('interpolates 1 -> 0.75 -> 0.25 over 48h and is 0 beyond', () => {
    expect(timeSimilarity(0)).toBe(1)
    expect(timeSimilarity(12 * H)).toBeCloseTo(0.875)
    expect(timeSimilarity(24 * H)).toBeCloseTo(0.75)
    expect(timeSimilarity(36 * H)).toBeCloseTo(0.5)
    expect(timeSimilarity(-48 * H)).toBeCloseTo(0.25)
    expect(timeSimilarity(49 * H)).toBe(0)
  })
})

describe('entitiesOf', () => {
  it('normalises amounts and percentages across spellings', () => {
    expect(entitiesOf('Pfizer gets $1.5 billion from Blackstone')).toContain('#1500000000')
    expect(entitiesOf('Pfizer secures up to $1.5B funding')).toContain('#1500000000')
    expect(entitiesOf('Boeing to cut 5% of workforce')).toContain('5%')
    expect(entitiesOf('Tesla recalls 200,000 vehicles')).toContain('#200000')
    expect(entitiesOf('Stock rises over 3 days')).toEqual(new Set()) // bare small numbers are not facts
  })
  it('finds curated terms and mid-headline capitalised names, minus the company itself and generic roles', () => {
    const e = entitiesOf('Apple supplier Foxconn faces probe as Tim Cook visits India', ['foxconn'], new Set(['apple']))
    expect(e).toContain('foxconn')
    expect(e).toContain('tim cook')
    expect(e).toContain('india')
    expect(e.has('apple')).toBe(false)
    expect(entitiesOf('Company says CEO Smith to retire', [], new Set()).has('ceo')).toBe(false)
  })
  it('ignores capitals in Title Case headlines, where they carry no information', () => {
    expect(entitiesOf('Chipmaker Chief Executive Steps Down After A Decade At The Helm')).toEqual(new Set())
  })
  it('similarity is shared over the smaller set, and null when either side has none', () => {
    expect(entitySimilarity(new Set(['a', 'b']), new Set(['a', 'b', 'c']))).toBe(1)
    expect(entitySimilarity(new Set(['a', 'b']), new Set(['c']))).toBe(0)
    expect(entitySimilarity(new Set(), new Set(['a']))).toBeNull()
  })
  it('weights 0.65/0.20/0.15 and renormalises without entities', () => {
    expect(pairScore(0.8, 1, 0)).toBeCloseTo(0.65 * 0.8 + 0.2 + 0.15)
    expect(pairScore(0.8, null, 0)).toBeCloseTo((0.65 * 0.8 + 0.15) / 0.8)
  })
})

describe('semanticMerges', () => {
  const run = (items, groups, extra = {}) => semanticMerges(items, groups ?? items.map((_, i) => [i]), { windowMs: WINDOW, threshold: 0.8, ...extra })

  it('merges groups of near-identical meaning close in time, and reports the score', () => {
    const items = [item(1, 'Chipmaker chief steps down', 0, unit(1, 0.05, 0)), item(2, 'Nvidia CEO resigns', 2, unit(1, 0.08, 0))]
    const merges = run(items)
    expect(merges).toHaveLength(1)
    expect(merges[0].members.sort()).toEqual([0, 1])
    expect(merges[0].score).toBeGreaterThan(0.8)
  })
  it('does not merge different meanings, or the same meaning outside the 48h window', () => {
    expect(run([item(1, 'a', 0, unit(1, 0, 0)), item(2, 'b', 1, unit(0, 1, 0))])).toEqual([])
    expect(run([item(1, 'a', 0, unit(1, 0, 0)), item(2, 'b', 72, unit(1, 0, 0))])).toEqual([])
  })
  it('uses average linkage: A~B and B~C do not chain A with C', () => {
    const a = unit(1, 0, 0), b = unit(1, 0.45, 0), c = unit(1, 0.9, 0) // adjacent pairs similar, ends far apart
    const items = [item(1, 'a', 0, a), item(2, 'b', 0, b), item(3, 'c', 0, c)]
    const merges = run(items, null, { threshold: 0.88 })
    expect(merges.length).toBeLessThanOrEqual(1)
    expect(merges.every((m) => m.members.length === 2)).toBe(true)
  })
  it('skips articles without an embedding and never pairs members of one lexical group', () => {
    expect(run([item(1, 'a', 0, unit(1, 0, 0)), item(2, 'b', 0, null)])).toEqual([])
    expect(run([item(1, 'a', 0, unit(1, 0, 0)), item(2, 'b', 0, unit(1, 0, 0))], [[0, 1]])).toEqual([])
  })
  it('logs merges and near misses with the numbers behind them', () => {
    const log = []
    run([item(1, 'x', 0, unit(1, 0, 0)), item(2, 'y', 0, unit(1, 0.01, 0)), item(3, 'z', 0, unit(1, 0.5, 0))], null, { threshold: 0.95, log })
    expect(log.find((e) => e.type === 'semantic-merge')).toMatchObject({ a: expect.any(String), b: expect.any(String), cosine: expect.any(Number), dtHours: 0 })
    expect(log.some((e) => e.type === 'near-miss')).toBe(true)
  })
})

describe('groupEvents with the semantic stage', () => {
  const profile = { ticker: 'XYZ', aliases: ['xyz'], people: [], supply: [], competitors: [], sectorTerms: [] }
  const items = () => [
    item(1, 'Quarterly results beat forecasts', 0, unit(1, 0.02, 0)),
    item(2, 'Zorblax earnings top expectations', 3, unit(1, 0.05, 0)), // no shared words: only the embedding links them
    item(3, 'Quarterly results beat forecasts again', 1, unit(1, 0.03, 0)) // lexically the same story as #1
  ]
  const opts = (semantic, extra = {}) => ({ profile, semantic, threshold: 0.8, ...extra })

  it("'off' and 'shadow' leave grouping to the lexical rules; 'shadow' still logs what it would do", () => {
    const log = []
    expect(groupEvents(items(), new Set(), opts('off')).length).toBe(2)
    const shadow = groupEvents(items(), new Set(), opts('shadow', { log }))
    expect(shadow.length).toBe(2)
    expect(shadow.every((e) => e.semantic === null)).toBe(true)
    expect(log.find((e) => e.type === 'semantic-merge')).toMatchObject({ applied: false, mode: 'shadow' })
  })
  it("'on' adds the semantic link without undoing the lexical one, and records the score", () => {
    const log = []
    const events = groupEvents(items(), new Set(), opts('on', { log }))
    expect(events.length).toBe(1)
    expect(events[0].size).toBe(3)
    expect(events[0].semantic).toBeGreaterThan(0.8)
    expect(log.find((e) => e.type === 'semantic-merge').applied).toBe(true)
  })
  it('articles without embeddings group exactly as before, in every mode', () => {
    const plain = items().map((it) => ({ ...it, article: { ...it.article, emb: undefined } }))
    for (const mode of ['off', 'shadow', 'on']) expect(groupEvents(plain, new Set(), opts(mode)).length).toBe(2)
  })
})
