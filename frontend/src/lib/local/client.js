// Drop-in replacement for the axios instance in ../api.js: same `api.get/post(path, {params})` calls,
// answered on the device (see ios/NewsEdge/NewsEdge/Networking/APIClient.swift for the same design).
import { TICKERS } from '../../data/tickers'
import * as A from './analytics'
import { createSources } from './sources'

const RETENTION_MS = 90 * 86_400_000
const DAY_MS = 86_400_000

const memoryStorage = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) } }

function hashId(s) { // FNV-1a, positive 32-bit: stable article identity across reloads
  let h = 0x811c9dc5
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) }
  return h >>> 0
}

export function createLocalApi({
  fetchImpl,
  storage = (typeof localStorage !== 'undefined' ? localStorage : memoryStorage()),
  score = A.sentiment,
  companyName = (t) => TICKERS.find((x) => x.symbol === String(t).toUpperCase())?.name ?? null,
  now = () => new Date()
} = {}) {
  const src = createSources({ fetchImpl, storage })
  const newsKey = (t) => `newsedge_news_v1_${A.yahooSymbol(t)}`
  const loadNews = (t) => { try { return JSON.parse(storage.getItem(newsKey(t)) || '[]') } catch { return [] } }
  const saveNews = (t, a) => { try { storage.setItem(newsKey(t), JSON.stringify(a)) } catch { /* quota: keep working from memory this session */ } }
  let queue = Promise.resolve() // serialize: summary/trend/news all call into the same cache

  /** Fresh Yahoo news merged into the cache; only new articles are scored. First sight of a ticker also backfills from Google. */
  function articles(ticker) {
    const run = async () => {
      const cached = loadNews(ticker)
      const byId = new Map(cached.map((a) => [a.id, a]))
      let fresh = [], failure
      try { fresh = await src.yahooNews(ticker) } catch (e) { failure = e }
      if (!cached.length) fresh = fresh.concat(await src.googleNews(ticker, companyName(ticker), { now: now() }))
      if (failure && !byId.size && !fresh.length) throw failure
      for (const a of fresh) {
        const id = hashId(a.url)
        if (byId.has(id)) continue
        const compound = score(a.headline)
        byId.set(id, { ...a, id, compound, sentiment_label: A.label(compound), source_weight: A.sourceWeight(a.source) })
      }
      const cutoff = now().getTime() - RETENTION_MS
      const merged = [...byId.values()].filter((a) => Date.parse(a.published_at) >= cutoff).sort((a, b) => b.published_at.localeCompare(a.published_at))
      saveNews(ticker, merged)
      return merged
    }
    const next = queue.then(run, run)
    queue = next.catch(() => {})
    return next
  }

  /** Window + headline dedup (newest kept) + relevance filter. Newest first. */
  async function relevant(ticker, sinceMs, minRelevance) {
    const seen = new Set(), out = []
    for (const a of await articles(ticker)) {
      const key = A.dedupKey(a.headline)
      if (Date.parse(a.published_at) < sinceMs || seen.has(key)) continue
      seen.add(key) // (Set#add returns the Set, so it can't double as a "was new" test)
      const rel = A.relevance(ticker, a.headline, a.symbols || [])
      if (rel < minRelevance) continue
      out.push({ ...a, relevance_score: Math.round(rel * 1e4) / 1e4 })
    }
    return out
  }

  const weighted = (items) => items.map((a) => a.compound * (a.source_weight ?? 1))
  const daysAgo = (d) => now().getTime() - d * DAY_MS
  /** Recency-weighted sentiment of `items` for a window/horizon of `days` (half-life = days / 3). */
  const signalOf = (items, days) => A.decayedMean(
    items.map((a) => ({ value: a.compound * (a.source_weight ?? 1), ageDays: (now().getTime() - Date.parse(a.published_at)) / DAY_MS })),
    days / 3)

  const routes = [
    ['GET', /^\/api\/news\/([^/]+)$/, async ([t], p) =>
      (await relevant(t, daysAgo(p.days ?? 30), p.min_relevance ?? 0.35)).slice(0, p.limit ?? 100)],
    ['GET', /^\/api\/news\/([^/]+)\/sentiment$/, async ([t], p) => {
      const items = await relevant(t, daysAgo(p.days ?? 7), p.min_relevance ?? 0.35)
      const w = weighted(items)
      const labels = { POSITIVE: 0, NEUTRAL: 0, NEGATIVE: 0 }
      items.forEach((a) => { labels[a.sentiment_label] += 1 })
      return { ticker: t.toUpperCase(), count: items.length, mean_compound: A.mean(w), std_compound: A.std(w), ewma_compound: signalOf(items, p.days ?? 7), label_distribution: labels }
    }],
    ['GET', /^\/api\/news\/([^/]+)\/trend$/, async ([t], p) => {
      const items = await relevant(t, daysAgo((p.hours ?? 72) / 24), p.min_relevance ?? 0.35)
      const buckets = new Map()
      for (const a of items) {
        const day = a.published_at.slice(0, 10)
        buckets.set(day, [...(buckets.get(day) || []), a.compound * (a.source_weight ?? 1)])
      }
      return { ticker: t.toUpperCase(), points: [...buckets.keys()].sort().map((d) => ({ bucket: `${d}T00:00:00`, mean_compound: A.mean(buckets.get(d)), article_count: buckets.get(d).length })) }
    }],
    ['GET', /^\/api\/price\/([^/]+)\/bars$/, async ([t], p) => (await src.bars(t)).slice(-(p.limit ?? 100))],
    ['GET', /^\/api\/price\/([^/]+)\/risk$/, async ([t], p) => {
      const [bars, bench] = await Promise.all([src.bars(t), src.bars(p.benchmark ?? 'SPY')])
      return A.riskMetrics(bars, bench)
    }],
    ['POST', /^\/api\/news\/subscribe\/([^/]+)$/, async () => ({ ok: true, status: 'local' })], // nothing to subscribe to
    ['POST', /^\/api\/predict\/([^/]+)\/sync$/, async ([t], _p, body) => {
      const horizon = body?.horizon_days ?? 5
      const [bars, one, seven, inHorizon, all] = await Promise.all([
        src.bars(t), relevant(t, daysAgo(1), 0.35), relevant(t, daysAgo(7), 0.35), relevant(t, daysAgo(horizon), 0.35), articles(t)])
      const week = all.filter((a) => Date.parse(a.published_at) >= daysAgo(7)).map((a) => a.compound)
      return A.predict({
        ticker: t, horizonDays: horizon, signal: signalOf(inHorizon, horizon),
        ewma1d: signalOf(one, 1), ewma7d: signalOf(seven, 7), sentimentVolatility: A.std(week),
        articleVolume24h: all.filter((a) => Date.parse(a.published_at) >= daysAgo(1)).length,
        price: A.priceFeatures(bars), now: now()
      })
    }]
  ]

  async function call(method, path, params = {}, body) {
    for (const [m, re, fn] of routes) {
      const hit = m === method && re.exec(path)
      if (hit) return { data: await fn(hit.slice(1).map(decodeURIComponent), params, body) }
    }
    throw new Error(`No local handler for ${method} ${path}`)
  }

  return {
    get: (path, { params } = {}) => call('GET', path, params),
    post: (path, body, { params } = {}) => call('POST', path, params, body)
  }
}

export const localApi = createLocalApi()
