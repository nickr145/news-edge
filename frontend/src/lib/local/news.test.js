import { describe, expect, it } from 'vitest'
import * as A from './analytics'
import * as N from './news'

const T0 = Date.parse('2026-11-11T12:00:00Z'), H = 3_600_000
const ig = (t) => N.ignoreTokens(N.profileFor(t, { NVDA: 'NVIDIA Corporation', TSLA: 'Tesla, Inc.', AAPL: 'Apple Inc.' }[t]))
const item = (headline, { source = 'X', hours = 0, tickers = ['NVDA'], value = 0.5 } = {}) =>
  ({ article: { id: headline + source, headline, source, source_weight: 1 }, exposure: { channel: 'direct', relevance: 0.85, weight: 1, sign: 1 }, tMs: T0 - hours * H, value })

describe('term matching', () => {
  it('matches whole terms only', () => {
    expect(N.hasTerm('amd unveils new chip', 'amd')).toBe(true)
    expect(N.hasTerm('islamdom news', 'amd')).toBe(false)         // inside a word
    expect(N.hasTerm('nvidia ceo steps down', 'nvidia ceo')).toBe(true)
    expect(N.hasTerm('s&p 500 closes higher', 's&p 500')).toBe(true)
    expect(N.hasTerm('the dental plan', 'ent')).toBe(false)
  })
})

describe('profiles', () => {
  it('merges curated, sector and catalog data', () => {
    const p = N.profileFor('NVDA', 'NVIDIA Corporation')
    expect(p.aliases).toContain('nvidia')
    expect(p.people).toContain('jensen huang')
    expect(p.supply).toEqual(expect.arrayContaining(['tsmc', 'hbm', 'euv']))   // ticker-specific + semis sector
    expect(p.competitors).toContain('amd')
    expect(p.macro).toContain('export controls')
    expect(p.sectorLabel).toBe('Semiconductors')
  })
  it('derives an alias from the catalog name for uncurated tickers, skipping generic first words', () => {
    expect(N.profileFor('CAT', 'Caterpillar Inc.').aliases).toEqual(expect.arrayContaining(['caterpillar']))
    expect(N.profileFor('GE', 'General Electric Co.').aliases).not.toContain('general')
  })
  it('every catalog ticker has a sector', async () => {
    const { TICKERS } = await import('../../data/tickers')
    const missing = TICKERS.filter((t) => !N.profileFor(t.symbol, t.name).sectorLabel).map((t) => t.symbol)
    expect(missing).toEqual([])
  })
})

describe('exposure: how a headline bears on the ticker', () => {
  const nvda = N.profileFor('NVDA', 'NVIDIA Corporation')
  const ex = (h, symbols = []) => N.exposureOf(nvda, h, symbols)
  it('direct: names the company, even without the ticker', () => {
    expect(ex('Nvidia unveils new AI chip')).toMatchObject({ channel: 'direct', sign: 1 })
    expect(ex('Nvidia unveils new AI chip').relevance).toBeGreaterThanOrEqual(0.4)
  })
  it('direct weight scales with relevance: tagged AND named counts in full, tag-only or mention-only less', () => {
    expect(ex('Nvidia posts record revenue', ['NVDA']).weight).toBe(1)                          // 0.85
    expect(ex('Nvidia unveils new AI chip').weight).toBeCloseTo(0.4 / 0.8, 12)                   // named only
    expect(ex('PwC spots a major shift in retirement money', ['NVDA', 'AAPL', 'MSFT']).weight)  // tag-only, 3 tickers: 0.37
      .toBeCloseTo(0.37 / 0.8, 12)
  })
  it('surnames catch headlines that omit the first name', () => {
    expect(ex("What Huang's resignation means for chipmakers")).toMatchObject({ channel: 'people', relevance: 0.8 })
  })
  it('leadership by name only (no company in the headline)', () => {
    expect(ex('Jensen Huang has been ousted')).toMatchObject({ channel: 'people', relevance: 0.8, weight: 0.8, sign: 1 })
  })
  it('supply chain / sector / macro are recognised with lower weights', () => {
    expect(ex('TSMC warns of capacity shortage')).toMatchObject({ channel: 'supply', relevance: 0.5 })
    expect(ex('Chip stocks tumble as rates jump')).toMatchObject({ channel: 'sector', relevance: 0.4 })
    expect(ex('US widens export controls on China')).toMatchObject({ channel: 'macro', relevance: 0.25 })
  })
  it('a competitor\'s news is inverted', () => {
    expect(ex('AMD wins huge cloud contract')).toMatchObject({ channel: 'competitor', sign: -1, weight: 0.3 })
  })
  it('unrelated headlines have no exposure', () => {
    expect(ex('Local bakery wins award')).toBeNull()
  })
  it('the strongest channel wins when several match', () => {
    expect(ex('TSMC export controls hit chip stocks').channel).toBe('supply') // supply 0.5 beats sector 0.4 / macro 0.25
  })
  it('inverse terms flip the sign for exposed sectors (airlines vs fuel)', () => {
    const dal = N.profileFor('DAL', 'Delta Air Lines Inc.')
    expect(N.exposureOf(dal, 'Oil prices jump on supply fears')).toMatchObject({ channel: 'macro', sign: -1 })
  })
})

describe('headline tokens and same-event matching', () => {
  const tokens = (h, t = 'NVDA') => N.headlineTokens(h, ig(t))
  const same = (a, b, t) => N.sameEvent(tokens(a, t), tokens(b, t))

  it('strips the publisher suffix, filler words and the company name', () => {
    expect([...tokens('Nvidia stock jumps on record data center revenue - Reuters')].sort()).toEqual(['center', 'data', 'jump', 'record', 'revenue'])
    expect(tokens("Tesla's 435,059 deliveries beat estimates", 'TSLA').has('435059')).toBe(true) // thousands separator removed
  })
  it('groups syndicated / lightly rewritten headlines', () => {
    expect(same('Tesla recalls 200,000 vehicles over safety defect - Reuters', 'Tesla recalls over 200,000 vehicles due to safety defect - AP', 'TSLA')).toBe(true)
    expect(same('Nvidia CEO Jensen Huang steps down', 'Jensen Huang steps down as Nvidia chief')).toBe(true)
  })
  it('keeps opposite or unrelated events apart', () => {
    expect(same('Nvidia stock jumps on record data center revenue', 'Nvidia stock falls after data center revenue misses')).toBe(false)
    expect(same('Nvidia unveils new gaming GPUs', 'Nvidia faces antitrust probe in China')).toBe(false)
  })
  it('a single shared generic word is not enough', () => {
    expect(same('Nvidia earnings preview', 'Nvidia earnings call transcript')).toBe(false)
  })
  it('identical informative words are one event even when few', () => {
    expect(same('Apple bad news - Reuters', 'Apple bad news - Bloomberg', 'AAPL')).toBe(true)
  })
})

describe('event grouping and weighting', () => {
  it('coverage boost is sublinear and capped', () => {
    expect(N.coverageBoost(1)).toBe(1)
    expect(N.coverageBoost(2)).toBeCloseTo(1 + 0.5 * Math.log(2), 12)
    expect(N.coverageBoost(10)).toBeCloseTo(1 + 0.5 * Math.log(10), 12)   // ~2.15: ten outlets != ten votes
    expect(N.coverageBoost(10_000)).toBe(2.5)
  })
  it('merges the same event across outlets inside 48h, one value and one vote', () => {
    const events = N.groupEvents([
      item('Tesla recalls 200,000 vehicles over safety defect - Reuters', { source: 'Reuters', value: -0.6 }),
      item('Tesla recalls over 200,000 vehicles due to safety defect - AP', { source: 'AP', value: -0.8, hours: 2 }),
      item('Tesla recalls 200,000 vehicles safety defect - CNBC', { source: 'CNBC', value: -0.7, hours: 3 }),
      item('Tesla unveils new robotaxi', { source: 'Verge', value: 0.6, hours: 5 })
    ], ig('TSLA'))
    expect(events).toHaveLength(2)
    const recall = events.find((e) => e.size === 3)
    expect(recall.outlets).toBe(3)
    expect(recall.value).toBeCloseTo((-0.6 - 0.8 - 0.7) / 3, 12)
    expect(recall.weight).toBeCloseTo(1 + 0.5 * Math.log(3), 12)
    expect(recall.tMs).toBe(T0 - 3 * H) // event time = first report
  })
  it('the same outlet repeating a story counts as one outlet', () => {
    const [e] = N.groupEvents([
      item('Nvidia ships record data center revenue', { source: 'Zacks' }), item('Nvidia ships record data center revenue today', { source: 'Zacks', hours: 1 })], ig('NVDA'))
    expect(e.size).toBe(2); expect(e.outlets).toBe(1); expect(e.weight).toBe(1)
  })
  it('does not merge identical headlines more than 48h apart (a new instance of the story)', () => {
    expect(N.groupEvents([item('Nvidia supply update', { hours: 0 }), item('Nvidia supply update', { hours: 60 })], ig('NVDA'))).toHaveLength(2)
  })
  it('an indirect article keeps its own weight and sign inside a mixed event', () => {
    const direct = item('Chip export curbs hit Nvidia hard', { value: -0.6 })
    const indirect = { ...item('Chip export curbs hit hard - Bloomberg', { source: 'Bloomberg', value: 0.5 }), exposure: { channel: 'macro', relevance: 0.25, weight: 0.25, sign: 1 } }
    const [e] = N.groupEvents([direct, indirect], ig('NVDA'))
    expect(e.size).toBe(2)
    expect(e.value).toBeCloseTo((1 * -0.6 + 0.25 * 0.5) / 1.25, 12)
    expect(e.channel).toBe('direct')
  })
})

describe('indirect queries', () => {
  it('builds one search per channel, with quoted phrases and a recency limit', () => {
    const qs = N.indirectQueries(N.profileFor('NVDA', 'NVIDIA Corporation'))
    expect(qs).toHaveLength(4)
    expect(qs[0]).toContain('"nvidia ceo"'); expect(qs[0]).toContain('"jensen huang"')
    expect(qs.every((q) => q.endsWith(' when:7d'))).toBe(true)
    expect(qs.every((q) => /^[\w\s"'().&,:\-–]{1,300}$/.test(q))).toBe(true) // acceptable to the proxy
  })
})

describe('weighted stats', () => {
  it('weightedMean/Std reduce to the plain ones with equal weights', () => {
    const x = [0.5, -0.2, 0.1, 0.8, -0.6]
    expect(A.weightedMean(x)).toBeCloseTo(0.12, 12)
    expect(A.weightedStd([1, 1], [1, 1])).toBe(0)
    expect(A.weightedMean([1, 0], [3, 1])).toBeCloseTo(0.75, 12)
  })
})

// ---- storylines --------------------------------------------------------------
describe('storyline damping', () => {
  const H = 3_600_000, NOW = Date.parse('2026-11-12T12:00:00Z')
  const ev = (i, hoursAgo, words) => ({ id: i, tMs: NOW - hoursAgo * H, tokens: new Set(words), weight: 1, damp: 1, storyline: null, storyRank: 1 })
  // 40 ordinary events spread over 20 days, each with its own distinctive words
  const ordinary = (n = 40) => Array.from({ length: n }, (_, i) => ev(i, 72 + (i * 440) / n, [`topic${i}`, `detail${i}`]))
  // a developing story: k events in the last 48h that all mention "zorblax" plus varied other words
  const story = (k, word = 'zorblax') => Array.from({ length: k }, (_, i) => ev(1000 + i, 1 + i * 2, [word, `angle${i}`, `view${i}`]))

  it('damps the k-th event of a bursting term by 1/sqrt(k), first report in full', () => {
    const out = N.dampStorylines([...ordinary(), ...story(20)])
    const s = out.filter((e) => e.storyline === 'zorblax').sort((a, b) => a.storyRank - b.storyRank)
    expect(s).toHaveLength(20)
    expect(s.map((e) => e.storyRank)).toEqual(Array.from({ length: 20 }, (_, i) => i + 1))   // earliest first
    expect(s[0].damp).toBe(1)
    expect(s[3].damp).toBeCloseTo(0.5, 12)                                                    // 4th: 1/sqrt(4)
    expect(s[15].damp).toBeCloseTo(0.25, 12)                                                  // 16th: 1/4, at the floor
    expect(s[19].damp).toBe(0.25)                                                             // never below the floor
    s.forEach((e) => expect(e.weight).toBeCloseTo(e.damp, 12))                                // weight starts at 1
  })

  it('leaves unrelated events alone', () => {
    const out = N.dampStorylines([...ordinary(), ...story(20)])
    out.filter((e) => e.storyline === null).forEach((e) => { expect(e.damp).toBe(1); expect(e.weight).toBe(1) })
  })

  it('never treats excluded (ordinary / topical) vocabulary as a storyline', () => {
    const out = N.dampStorylines([...ordinary(), ...story(20)], new Set(['zorblax']))
    expect(out.every((e) => e.storyline === null && e.damp === 1)).toBe(true)
  })

  it('needs enough context: fewer than 30 events are returned untouched', () => {
    const few = story(12)
    expect(N.dampStorylines(few)).toBe(few)
  })

  it('steady vocabulary is not a burst when older events provide a baseline', () => {
    // "regular" is in ~30% of events at a constant rate all month
    const steady = Array.from({ length: 60 }, (_, i) => ev(i, 6 + i * 11, i % 3 === 0 ? ['regular', `x${i}`] : [`y${i}`, `z${i}`]))
    expect(N.dampStorylines(steady).every((e) => e.storyline === null)).toBe(true)
  })

  it('with no baseline (a story fills the whole sample) it needs more events and a higher share', () => {
    // every event within ~2 days: no events outside the +/-72h window to compare against
    const base = Array.from({ length: 50 }, (_, i) => ev(i, 1 + i * 0.9, [`t${i}`, `u${i}`]))
    const small = base.map((e, i) => (i < 5 ? { ...e, tokens: new Set(['minorword', `a${i}`]) } : e))   // 5 events (10%): too few
    expect(N.dampStorylines(small).every((e) => e.storyline === null)).toBe(true)
    const big = base.map((e, i) => (i < 12 ? { ...e, tokens: new Set(['majorword', `a${i}`]) } : e))    // 12 events (24%): a story
    const out = N.dampStorylines(big)
    expect(out.filter((e) => e.storyline === 'majorword')).toHaveLength(12)
  })

  it('only events within 72h pile up: a long-running story plateaus instead of ranking forever', () => {
    // a piece every 6 hours for 6 days (24 events), over plenty of ordinary context
    const long = Array.from({ length: 24 }, (_, i) => ev(3000 + i, 2 + i * 6, ['zorblax', `a${i}`, `b${i}`]))
    const out = N.dampStorylines([...ordinary(60), ...long]).filter((e) => e.storyline === 'zorblax')
    expect(out.length).toBeGreaterThanOrEqual(20)
    expect(Math.max(...out.map((e) => e.storyRank))).toBeLessThanOrEqual(13)   // 72h / 6h = 12 earlier events + itself
    expect(Math.max(...out.map((e) => e.storyRank))).toBeGreaterThanOrEqual(10)
    expect(out.every((e) => e.damp >= 0.25)).toBe(true)
  })

  it('storylineExclusions: ordinary words and profile vocabulary are out, people stay in, chronic newsmakers go out', () => {
    const nvda = N.storylineExclusions(N.profileFor('NVDA', 'NVIDIA Corporation'))
    expect(nvda.has('ai')).toBe(true)                  // ubiquitous headline word
    expect(nvda.has('tsmc')).toBe(true)                // NVDA's own topical vocabulary
    expect(nvda.has('huang')).toBe(false)              // a leadership story must stay detectable
    const tsla = N.storylineExclusions(N.profileFor('TSLA', 'Tesla, Inc.'))
    expect(tsla.has('musk')).toBe(true)                // chronic: Musk is in nearly every Tesla story
    expect(tsla.has('spacex')).toBe(false)             // but a Tesla-SpaceX merger story is detectable
  })

  it('corporate suffixes and exchange tags are not informative tokens', () => {
    expect([...N.headlineTokens('JPMorgan Chase & Co. (NYSE:JPM) Shares Down 1.9%')]).not.toEqual(expect.arrayContaining(['co']))
    expect(N.headlineTokens('Acme Corp Inc Ltd NYSE Nasdaq results').has('corp')).toBe(false)
  })
})

