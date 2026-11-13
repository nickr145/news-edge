import { beforeEach, describe, expect, it, vi } from 'vitest'
import handler from '../../../../api/proxy.mjs'
import { createLocalApi } from './client'
import { createSources } from './sources'

// ---- fixtures -------------------------------------------------------------
const NOW = new Date('2026-11-12T12:00:00Z')
const BASE = new Date('2026-11-11T12:00:00Z') // yesterday noon UTC, so a/b/d share a UTC day
const memStorage = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v), keys: () => [...m.keys()] } }
const score = vi.fn((h) => (h.includes('good') ? 0.8 : h.includes('bad') ? -0.6 : 0))

const search = (items) => JSON.stringify({ news: items.map(({ title, publisher = 'Zacks', time, tickers = ['AAPL'] }) => ({ uuid: `${title}|${publisher}`, title, publisher, link: `https://x.test/${title.replace(/\W/g, '')}${publisher}`, providerPublishTime: Math.floor(time.getTime() / 1000), relatedTickers: tickers })) })
const chart = (closes, stamps) => JSON.stringify({ chart: { result: [{ timestamp: stamps, indicators: { quote: [{ open: closes, high: closes, low: closes, close: closes, volume: closes.map(() => 1) }] } }] } })
const nasdaqJSON = JSON.stringify({ data: { tradesTable: { rows: [
  { date: '11/11/2026', close: '$355.63', volume: '34,453,480', open: '$349.545', high: '$355.91', low: '$349.325' },
  { date: '11/10/2026', close: '$348.51', volume: '29,756,060', open: '$351.35', high: '$353.87', low: '$346.4605' },
  { date: '11/09/2026', close: 'N/A', volume: '1', open: '$1', high: '$1', low: '$1' }] } } })
const RSS = `<?xml version="1.0"?><rss><channel>
<item><title>Apple unveils new chip - The Verge</title><link>https://g.test/1</link><pubDate>Mon, 09 Nov 2026 10:00:00 GMT</pubDate><source url="x">The Verge</source></item>
<item><title><![CDATA[AAPL shares climb on services growth - Reuters]]></title><link>https://g.test/2</link><pubDate>Tue, 10 Nov 2026 10:00:00 GMT</pubDate><source url="x">Reuters</source></item>
<item><title>Oil prices slide again - Bloomberg</title><link>https://g.test/3</link><pubDate>Tue, 10 Nov 2026 12:00:00 GMT</pubDate><source url="x">Bloomberg</source></item>
</channel></rss>`

/** fetch stub: routes on the proxy's `target` param; records hits. */
function net(routes) {
  const hits = {}
  const fn = async (url) => {
    const target = new URL(url, 'http://x').searchParams.get('target')
    hits[target] = (hits[target] || 0) + 1
    const r = routes[target]
    if (!r || r === 'down') throw new TypeError('network down')
    const { status = 200, body = '' } = typeof r === 'function' ? r(url) : r
    return { ok: status >= 200 && status < 300, status, text: async () => body }
  }
  fn.hits = hits
  return fn
}
const make = (routes, extra = {}) => { const fetchImpl = net(routes); const storage = memStorage(); return { fetchImpl, storage, api: createLocalApi({ fetchImpl, storage, score, companyName: () => 'Apple Inc.', now: () => NOW, ...extra }) } }

beforeEach(() => { score.mockClear() })

// ---- parsing --------------------------------------------------------------
describe('sources parsing', () => {
  const src = createSources({ fetchImpl: net({}) })
  it('nasdaq rows: skips bad rows, returns oldest first', () => {
    const bars = src.parseNasdaq(nasdaqJSON)
    expect(bars.map((b) => b.close)).toEqual([348.51, 355.63])
    expect(bars[0].volume).toBe(29_756_060)
    expect(src.parseNasdaq('<html>blocked</html>')).toEqual([])
    expect(src.parseNasdaq('{"data":{"tradesTable":null}}')).toEqual([])
  })
  it('google RSS: strips publisher suffix, CDATA, sorts, tags by mention, limits', () => {
    const items = src.parseGoogleRSS(RSS, 'AAPL', 'Apple Inc.', 30)
    expect(items.map((i) => i.headline)).toEqual(['Oil prices slide again', 'AAPL shares climb on services growth', 'Apple unveils new chip'])
    expect(items.map((i) => i.source)).toEqual(['Bloomberg', 'Reuters', 'The Verge'])
    expect(items.map((i) => i.symbols)).toEqual([[], ['AAPL'], ['AAPL']])
    expect(src.parseGoogleRSS(RSS, 'AAPL', null, 1)).toHaveLength(1)
  })
})

// ---- price sources --------------------------------------------------------
describe('bars', () => {
  it('skips null candles', async () => {
    const { api } = make({ chart: { body: chart([1, null, 3], [1767225600, 1767312000, 1767398400]) } })
    const { data } = await api.get('/api/price/AAPL/bars', { params: { limit: 10 } })
    expect(data.map((b) => b.close)).toEqual([1, 3])
  })
  it('falls back Yahoo -> Nasdaq -> cache -> error', async () => {
    const storage = memStorage()
    const a = createLocalApi({ fetchImpl: net({ chart: { status: 500 }, nasdaq: { body: nasdaqJSON } }), storage, now: () => NOW })
    expect((await a.get('/api/price/AAPL/bars')).data.map((b) => b.close)).toEqual([348.51, 355.63])
    const b = createLocalApi({ fetchImpl: net({ chart: 'down', nasdaq: 'down' }), storage, now: () => NOW })
    expect((await b.get('/api/price/AAPL/bars')).data.map((x) => x.close)).toEqual([348.51, 355.63]) // served from localStorage
    const c = createLocalApi({ fetchImpl: net({ chart: 'down', nasdaq: 'down' }), storage: memStorage(), now: () => NOW })
    await expect(c.get('/api/price/AAPL/bars')).rejects.toThrow()
  })
  it('unknown symbol yields [] not an error (Yahoo 404, Nasdaq no rows)', async () => {
    const { api } = make({ chart: { status: 404 }, nasdaq: { body: '{"data":{"tradesTable":{"rows":[]}}}' } })
    expect((await api.get('/api/price/ZZZZQ/bars')).data).toEqual([])
  })
  it('risk of identical series: beta 1, no drawdown', async () => {
    const closes = Array.from({ length: 40 }, (_, i) => 100 + i), stamps = closes.map((_, i) => 1767225600 + i * 86400)
    const { api } = make({ chart: { body: chart(closes, stamps) } })
    const { data } = await api.get('/api/price/AAPL/risk', { params: { benchmark: 'SPY' } })
    expect(data.beta_to_benchmark).toBeCloseTo(1, 9); expect(data.max_drawdown).toBe(0); expect(data.high_water_mark).toBe(139)
  })
})

// ---- news store + endpoints ----------------------------------------------
const ago = (ms, from = BASE) => new Date(from.getTime() - ms)
const H = 3_600_000, D = 86_400_000

describe('news cache', () => {
  it('scores only new articles and merges across reloads', async () => {
    const first = search([{ title: 'AAPL good one', time: BASE }])
    const routes = { search: { body: first }, gnews: 'down' }
    const { api, storage } = make(routes)
    expect((await api.get('/api/news/AAPL', { params: { days: 30 } })).data).toHaveLength(1)
    expect(score).toHaveBeenCalledTimes(1)
    // "relaunch": new client on the same storage sees an old + a new article, scoring only the new one
    const api2 = createLocalApi({ fetchImpl: net({ search: { body: search([{ title: 'AAPL good one', time: BASE }, { title: 'AAPL bad two', time: new Date(BASE.getTime() + 60_000) }]) }, gnews: 'down' }), storage, score, now: () => NOW })
    const { data } = await api2.get('/api/news/AAPL', { params: { days: 30 } })
    expect(data.map((a) => a.headline)).toEqual(['AAPL bad two', 'AAPL good one'])
    expect(score).toHaveBeenCalledTimes(2)
  })
  it('prunes >90 days and backfills from Google once per ticker', async () => {
    const { api, fetchImpl } = make({ search: { body: search([{ title: 'AAPL good fresh', time: BASE }, { title: 'AAPL good ancient', time: ago(100 * D) }]) }, gnews: { body: '<rss><channel></channel></rss>' } })
    expect((await api.get('/api/news/AAPL', { params: { days: 365 } })).data.map((a) => a.headline)).toEqual(['AAPL good fresh'])
    expect(fetchImpl.hits.gnews).toBe(4) // one request per weekly window
    await api.get('/api/news/AAPL', { params: { days: 365 } })
    expect(fetchImpl.hits.gnews).toBe(4) // cache exists: no second backfill
  })
  it('backfills history when Yahoo is empty, then serves the cache offline', async () => {
    const { api, storage } = make({ search: { body: '{"news":[]}' }, gnews: { body: RSS } })
    expect((await api.get('/api/news/AAPL', { params: { days: 30 } })).data.length).toBeGreaterThan(0)
    const offline = createLocalApi({ fetchImpl: net({ search: 'down', gnews: 'down' }), storage, score, now: () => NOW })
    expect((await offline.get('/api/news/AAPL', { params: { days: 30 } })).data.length).toBeGreaterThan(0)
    const empty = createLocalApi({ fetchImpl: net({ search: 'down', gnews: 'down' }), storage: memStorage(), score, now: () => NOW })
    await expect(empty.get('/api/news/AAPL')).rejects.toThrow()
  })
})

describe('endpoints', () => {
  const items = [
    { title: 'AAPL good earnings', time: BASE },
    { title: 'Apple bad news - Reuters', publisher: 'Reuters', time: ago(H) },
    { title: 'Apple bad news - Bloomberg', publisher: 'Bloomberg', time: ago(2 * H) }, // dup of the Reuters one
    { title: 'Market roundup', time: ago(2 * H), tickers: ['AAPL', 'MSFT', 'NVDA', 'TSLA', 'AMZN', 'GOOG', 'META', 'NFLX'] }, // relevance 0.20
    { title: 'AAPL good old', time: ago(10 * D) }
  ]
  const setup = () => make({ search: { body: search(items) }, gnews: 'down' })

  it('filters, dedups and limits like the backend', async () => {
    const { api } = setup()
    const week = (await api.get('/api/news/AAPL', { params: { days: 7 } })).data
    expect(week.map((a) => a.headline)).toEqual(['AAPL good earnings', 'Apple bad news - Reuters'])
    expect([week[0].relevance_score, week[1].relevance_score]).toEqual([0.85, 0.45])
    expect((await api.get('/api/news/AAPL', { params: { days: 30 } })).data).toHaveLength(3)
    expect((await api.get('/api/news/AAPL', { params: { days: 7, min_relevance: 0.2 } })).data).toHaveLength(3)
    expect((await api.get('/api/news/AAPL', { params: { days: 7, limit: 1 } })).data).toHaveLength(1)
  })
  it('summary: weighted mean, recency-weighted EWMA, labels', async () => {
    const { data: s } = await setup().api.get('/api/news/AAPL/sentiment', { params: { days: 7 } })
    expect(s.count).toBe(2)
    expect(s.label_distribution).toEqual({ POSITIVE: 1, NEUTRAL: 0, NEGATIVE: 1 })
    expect(s.mean_compound).toBeCloseTo(0.025, 9) // (0.8*1.0 + -0.6*1.25) / 2
    // recency-weighted: b is 1h older than a; half-life = 7/3 days, so b's weight is r = 0.5^((1/24)/(7/3)) of a's
    const r = 0.5 ** ((1 / 24) / (7 / 3))
    expect(s.ewma_compound).toBeCloseTo((0.8 - 0.75 * r) / (1 + r), 9)
  })
  it('trend buckets by UTC day with ISO bucket strings', async () => {
    const { data: t } = await setup().api.get('/api/news/AAPL/trend', { params: { hours: 24 * 30 } })
    expect(t.points.map((p) => p.article_count)).toEqual([1, 2])
    expect(t.points[1].bucket.slice(0, 10)).toBe('2026-11-11')
    expect(t.points[1].mean_compound).toBeCloseTo(0.025, 9)
  })
  it('subscribe is a no-op and predict returns the fallback rule', async () => {
    const closes = Array.from({ length: 40 }, (_, i) => 100 + i), stamps = closes.map((_, i) => 1767225600 + i * 86400)
    const { api } = make({ search: { body: search(items) }, gnews: 'down', chart: { body: chart(closes, stamps) } })
    expect((await api.post('/api/news/subscribe/AAPL', null, { params: {} })).data.ok).toBe(true)
    const { data: p } = await api.post('/api/predict/AAPL/sync', { horizon_days: 14 })
    expect(p.horizon_days).toBe(14)
    expect(['RISE', 'STABLE', 'FALL']).toContain(p.recommendation)
    expect(p.feature_importances.__model.version).toBe('fallback_rule_v2')
  })
  it('subscribe/predict stay wired when the horizon is omitted (defaults to 5 days)', async () => {
    const closes = Array.from({ length: 40 }, (_, i) => 100 + i), stamps = closes.map((_, i) => 1767225600 + i * 86400)
    const { api } = make({ search: { body: search(items) }, gnews: 'down', chart: { body: chart(closes, stamps) } })
    expect((await api.post('/api/predict/AAPL/sync', {})).data.horizon_days).toBe(5)
  })
  it('unknown routes fail loudly', async () => {
    await expect(setup().api.get('/api/nope')).rejects.toThrow(/No local handler/)
  })
})

// ---- the proxy ------------------------------------------------------------
describe('proxy handler', () => {
  const run = async (query) => {
    const res = { headers: {}, setHeader(k, v) { this.headers[k] = v }, end(b) { this.body = b } }
    await handler({ query }, res)
    return res
  }
  it('rejects unknown targets and malformed parameters (no open proxy)', async () => {
    for (const q of [{ target: 'evil', symbol: 'AAPL' }, { target: 'chart', symbol: 'AAPL/../x' }, { target: 'chart' }, { target: 'nasdaq', symbol: 'AAPL', assetclass: 'x', fromdate: '2026-01-01', todate: '2026-01-02' },
      { target: 'nasdaq', symbol: 'AAPL', assetclass: 'stocks', fromdate: 'x', todate: '2026-01-02' }, { target: 'gnews', symbol: 'AAPL', after: '2026-01-01', before: 'DROP' }]) {
      expect((await run(q)).statusCode).toBe(400)
    }
  })
  it('forwards only to the fixed upstream hosts', async () => {
    const urls = []
    vi.stubGlobal('fetch', async (u) => { urls.push(u); return { status: 200, headers: { get: () => 'application/json' }, arrayBuffer: async () => new TextEncoder().encode('{}').buffer } })
    await run({ target: 'chart', symbol: 'BRK-B' })
    await run({ target: 'search', symbol: 'AAPL' })
    await run({ target: 'nasdaq', symbol: 'BRK-B', assetclass: 'stocks', fromdate: '2026-01-01', todate: '2026-02-01' })
    await run({ target: 'gnews', symbol: 'AAPL', after: '2026-01-01', before: '2026-01-08' })
    vi.unstubAllGlobals()
    expect(urls.map((u) => new URL(u).host)).toEqual(['query1.finance.yahoo.com', 'query1.finance.yahoo.com', 'api.nasdaq.com', 'news.google.com'])
    expect(urls[2]).toContain('/api/quote/BRK.B/historical')
  })
})

// ---- the window and the horizon actually matter ---------------------------
describe('recency-weighted sentiment', () => {
  // One fresh negative headline (1h old) and three older positives (4 days old).
  const mood = [
    { title: 'AAPL bad flash', time: new Date(NOW.getTime() - H) },
    ...['A', 'B', 'C'].map((x) => ({ title: `AAPL good ${x}`, time: new Date(NOW.getTime() - 4 * D) }))
  ]
  const closes = Array.from({ length: 40 }, (_, i) => 100 + i), stamps = closes.map((_, i) => 1767225600 + i * 86400)
  const setup = () => make({ search: { body: search(mood) }, gnews: 'down', chart: { body: chart(closes, stamps) } })

  it('the 1 / 5 / 14 day horizons give different recommendations', async () => {
    const { api } = setup()
    const rec = async (h) => (await api.post('/api/predict/AAPL/sync', { horizon_days: h })).data
    const [d1, d5, d14] = [await rec(1), await rec(5), await rec(14)]
    expect([d1.recommendation, d5.recommendation, d14.recommendation]).toEqual(['FALL', 'STABLE', 'RISE'])
    expect(d1.sentiment_score).toBeCloseTo(-0.6, 9)            // only the fresh negative is inside 1 day
    expect(d1.sentiment_score).toBeLessThan(d5.sentiment_score)
    expect(d5.sentiment_score).toBeLessThan(d14.sentiment_score) // a longer horizon lets the older positives count
    expect(d1.confidence).toBeCloseTo(0.52 + 0.6 * 0.35, 9)
  })

  it('the EWMA stat changes with the window', async () => {
    const { api } = setup()
    const ewma = async (days) => (await api.get('/api/news/AAPL/sentiment', { params: { days } })).data.ewma_compound
    expect((await ewma(30)) - (await ewma(7))).toBeGreaterThan(0.05) // longer window, slower decay, older positives matter more
    expect(await ewma(7)).not.toBeCloseTo(await ewma(5), 3)
  })
})
