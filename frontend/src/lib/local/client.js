// Drop-in replacement for the axios instance in ../api.js: same `api.get/post(path, {params})` calls,
// answered on the device (see ios/NewsEdge/NewsEdge/Networking/APIClient.swift for the same design).
import { TICKERS } from '../../data/tickers'
import * as A from './analytics'
import * as N from './news'
import config from '../../data/newsConfig.json'
import { createSources } from './sources'
import { createEmbedder, embeddingText, quantize } from './embeddings'

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
  now = () => new Date(),
  embedder = (typeof window === 'undefined' ? null : createEmbedder()), // tests and SSR never download the model
  semanticMode, // 'off' | 'shadow' | 'on'; default: events.semantic.mode in data/news_config.json
  semanticThreshold // default: events.semantic.threshold (only evaluation overrides it)
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
      const sym = A.yahooSymbol(ticker)
      if (!indirectDone.has(sym)) {
        indirectDone.add(sym)
        const profile = profileOf(ticker)
        const found = (await Promise.all(N.indirectQueries(profile).map((q) => src.googleSearch(q).catch(() => [])))).flat()
        fresh = fresh.concat(found.filter((a) => N.exposureOf(profile, a.headline, a.symbols || [])))
      }
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
      embedMissing(ticker) // background: never delays the articles themselves
      return merged
    }
    const next = queue.then(run, run)
    queue = next.catch(() => {})
    return next
  }

  /**
   * Gives every cached article without one an embedding (stored as `emb`, int8 base64), once ever: toggling a window or
   * relevance never re-embeds. Fire-and-forget; articles without one are simply grouped lexically. Storage is re-read
   * after the await so articles saved meanwhile are not overwritten.
   */
  let embedding = Promise.resolve()
  function embedMissing(ticker) {
    if (!embedder) return
    embedding = embedding.then(async () => {
      const todo = loadNews(ticker).filter((a) => !a.emb)
      if (!todo.length) return
      const vecs = await embedder.embed(todo.map((a) => embeddingText(a.headline, companyName(ticker))))
      if (!vecs) return
      const emb = new Map(todo.map((a, i) => [a.id, quantize(vecs[i])]))
      saveNews(ticker, loadNews(ticker).map((a) => (emb.has(a.id) && !a.emb ? { ...a, emb: emb.get(a.id) } : a)))
    }).catch(() => {})
  }

  const decisions = new Map() // ticker -> why the last grouping pass merged (or nearly merged) events; see debug.decisions
  const indirectDone = new Set() // tickers whose leadership/supply/sector/macro searches already ran this session

  /** Cached news + (once per session) the indirect searches, whose results are kept only if they bear on the ticker. */
  const profileOf = (t) => N.profileFor(t, companyName(t))

  /**
   * Window + relevance (direct or indirect) + event grouping. Every aggregate below works on events, so a story
   * echoed by many outlets is one vote with a bounded coverage boost, and indirect channels carry their sign/weight.
   */
  async function eventsFor(ticker, sinceMs, minRelevance) {
    const profile = profileOf(ticker)
    const items = []
    // Storyline detection needs context (what is normal vs a burst), so look back at least 30 days even for a 1-day window.
    const contextMs = Math.min(sinceMs, now().getTime() - config.storylines.context_days * DAY_MS)
    for (const a of await articles(ticker)) {
      const tMs = Date.parse(a.published_at)
      if (tMs < contextMs) continue
      const exposure = N.exposureOf(profile, a.headline, a.symbols || [])
      if (!exposure || exposure.relevance < minRelevance) continue
      items.push({ article: a, exposure, tMs, value: a.compound * (a.source_weight ?? 1) * exposure.sign })
    }
    const log = []
    const grouped = N.groupEvents(items, N.ignoreTokens(profile), { profile, log, semantic: semanticMode, threshold: semanticThreshold })
    decisions.set(A.yahooSymbol(ticker), log)
    return N.dampStorylines(grouped, N.storylineExclusions(profile)).filter((e) => e.tMs >= sinceMs)
  }

  const withoutEmb = ({ emb, ...rest }) => rest // embeddings stay in the cache, never in what the UI receives
  const daysAgo = (d) => now().getTime() - d * DAY_MS
  const round4 = (x) => Math.round(x * 1e4) / 1e4
  /** Recency-weighted sentiment of events for a window/horizon of `days` (half-life = days / 3). */
  const signalOf = (events, days) => A.decayedMean(
    events.map((e) => ({ value: e.value, weight: e.weight, ageDays: (now().getTime() - e.tMs) / DAY_MS })), days / 3)

  const routes = [
    ['GET', /^\/api\/news\/([^/]+)$/, async ([t], p) =>
      (await eventsFor(t, daysAgo(p.days ?? 30), p.min_relevance ?? 0.35)).slice(0, p.limit ?? 100)
        .map((e) => ({ ...withoutEmb(e.rep), relevance_score: round4(e.relevance), channel: e.channel, event_size: e.size, event_outlets: e.outlets,
          storyline: e.storyline, story_rank: e.storyRank, story_damp: round4(e.damp), semantic_score: e.semantic == null ? null : round4(e.semantic) }))],
    ['GET', /^\/api\/news\/([^/]+)\/sentiment$/, async ([t], p) => {
      const events = await eventsFor(t, daysAgo(p.days ?? 7), p.min_relevance ?? 0.35)
      const values = events.map((e) => e.value), weights = events.map((e) => e.weight)
      const labels = { POSITIVE: 0, NEUTRAL: 0, NEGATIVE: 0 }
      events.forEach((e) => { labels[A.label(e.value)] += 1 })
      return {
        ticker: t.toUpperCase(), count: events.length, article_count: events.reduce((a, e) => a + e.size, 0),
        mean_compound: A.weightedMean(values, weights), std_compound: A.weightedStd(values, weights),
        ewma_compound: signalOf(events, p.days ?? 7), label_distribution: labels
      }
    }],
    ['GET', /^\/api\/news\/([^/]+)\/trend$/, async ([t], p) => {
      const events = await eventsFor(t, daysAgo((p.hours ?? 72) / 24), p.min_relevance ?? 0.35)
      const buckets = new Map()
      for (const e of events) {
        const day = new Date(e.tMs).toISOString().slice(0, 10)
        buckets.set(day, [...(buckets.get(day) || []), e])
      }
      return { ticker: t.toUpperCase(), points: [...buckets.keys()].sort().map((d) => ({
        bucket: `${d}T00:00:00`, mean_compound: A.weightedMean(buckets.get(d).map((e) => e.value), buckets.get(d).map((e) => e.weight)), article_count: buckets.get(d).length })) }
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
        src.bars(t), eventsFor(t, daysAgo(1), 0.35), eventsFor(t, daysAgo(7), 0.35), eventsFor(t, daysAgo(horizon), 0.35), articles(t)])
      return A.predict({
        ticker: t, horizonDays: horizon, signal: signalOf(inHorizon, horizon),
        ewma1d: signalOf(one, 1), ewma7d: signalOf(seven, 7), sentimentVolatility: A.weightedStd(seven.map((e) => e.value), seven.map((e) => e.weight)),
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
    post: (path, body, { params } = {}) => call('POST', path, params, body),
    /** Explainability: the semantic merges and near misses behind the last grouping of `ticker` (see semantic.js). */
    debug: { decisions: (ticker) => decisions.get(A.yahooSymbol(ticker)) || [] }
  }
}

export const localApi = createLocalApi()
