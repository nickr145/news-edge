// Semantic event matching: decides whether two articles that the lexical rules did NOT link still describe the same
// event, from sentence embeddings + shared entities + closeness in time. Lexical links always win and are never undone;
// this only ever adds links, and conservatively: groups merge by average linkage (a chain of "kind of similar"
// pairs cannot snowball) and only above `events.semantic.threshold` (data/news_config.json).
import config from '../../data/newsConfig.json'
import { cosine, dequantize } from './embeddings'
import { hasTerm } from './tokens'

const SEM = config.events.semantic
const HOUR = 3_600_000
const MAGNITUDE = { trillion: 1e12, billion: 1e9, bn: 1e9, b: 1e9, million: 1e6, mn: 1e6, m: 1e6, thousand: 1e3, k: 1e3 }
const GENERIC_CAPS = new Set(['ceo', 'cfo', 'coo', 'cto', 'ipo', 'q1', 'q2', 'q3', 'q4']) // capitalised, but in half of all headlines

const vectors = new Map() // emb string -> Float32Array (dequantising 300 articles on every call would be wasteful)
export function vectorOf(article) {
  if (!article.emb) return null
  let v = vectors.get(article.emb)
  if (!v) {
    if (vectors.size > 20_000) vectors.clear()
    v = dequantize(article.emb)
    vectors.set(article.emb, v)
  }
  return v
}

/** Linear interpolation over events.semantic.time_similarity ([[hours, similarity], ...]); 0 beyond the last point. */
export function timeSimilarity(dtMs, points = SEM.time_similarity) {
  const h = Math.abs(dtMs) / HOUR
  if (h > points[points.length - 1][0]) return 0
  for (let i = 1; i < points.length; i++) {
    if (h <= points[i][0]) {
      const [h0, v0] = points[i - 1], [h1, v1] = points[i]
      return v0 + ((v1 - v0) * (h - h0)) / (h1 - h0)
    }
  }
  return points[points.length - 1][1]
}

/**
 * What a headline is about, beyond the company itself: amounts ("$5 billion", "20%"), curated people/suppliers/
 * competitors/sector terms from the profile, and capitalised phrases (skipped for Title Case headlines, where
 * capitals say nothing). Lower-cased. `ignore` = the company's own name tokens.
 */
export function entitiesOf(headline, terms = [], ignore = new Set()) {
  const out = new Set()
  const text = String(headline || '').replace(/\s*[-–|]\s*[A-Za-z][\w\s.&]{1,40}$/, '').replace(/['’]s\b/g, '')
  const lower = text.toLowerCase()
  for (const m of lower.matchAll(/([$€£])?\s?(\d[\d,]*(?:\.\d+)?)\s?(trillion|billion|million|thousand|bn|mn|%|percent|[bmk]\b)?/g)) {
    const n = parseFloat(m[2].replace(/,/g, ''))
    const unit = m[3]
    if (unit === '%' || unit === 'percent') out.add(`${n}%`)
    else if (unit && MAGNITUDE[unit]) out.add(`#${n * MAGNITUDE[unit]}`)
    else if (m[1] || n >= 1000) out.add(`#${n}`) // "$5", "200,000"; bare small numbers are dates and counts
  }
  for (const t of terms) if (hasTerm(lower, t)) out.add(t)
  const words = text.split(/\s+/).map((w) => w.replace(/^[^A-Za-z0-9$]+|[^A-Za-z0-9]+$/g, '')).filter(Boolean)
  const cap = (w) => /^[A-Z]/.test(w)
  const long = words.filter((w) => w.length > 3)
  if (long.length && long.filter(cap).length / long.length < 0.7) { // not Title Case
    for (let i = 0; i < words.length; i++) {
      if (!cap(words[i])) continue
      let j = i
      while (j + 1 < words.length && cap(words[j + 1])) j++
      const run = words.slice(i, j + 1).map((w) => w.toLowerCase())
      i = j
      if (run.length === 1 && (i === 0 || run[0].length < 2)) continue // a sentence-initial word alone is just a word
      const phrase = run.filter((w) => !ignore.has(w) && !GENERIC_CAPS.has(w))
      if (phrase.length) out.add(phrase.join(' '))
    }
  }
  return out
}

/** Shared entities over the smaller set (so a headline that mentions fewer things is not penalised); null if either has none. */
export function entitySimilarity(a, b) {
  if (!a.size || !b.size) return null
  let shared = 0
  for (const e of a) if (b.has(e)) shared++
  return shared / Math.min(a.size, b.size)
}

/** 0.65 semantic + 0.20 entity + 0.15 time; with no entities on one side the entity term is dropped and the rest renormalised. */
export function pairScore(cos, entity, dtMs) {
  const w = SEM.weights, time = timeSimilarity(dtMs)
  return entity == null ? (w.semantic * cos + w.time * time) / (w.semantic + w.time) : w.semantic * cos + w.entity * entity + w.time * time
}

/**
 * `groups`: arrays of item indexes the lexical rules already linked. Returns the semantic merges, each
 * { members: [item indexes], score }. Average linkage over all cross pairs that have embeddings (a pair more than
 * `windowMs` apart scores 0), so a merge needs the groups as a whole to be close, not one lucky pair.
 * `log` (optional array) receives every merge and every near miss with the numbers behind the decision.
 */
export function semanticMerges(items, groups, { terms = [], ignore = new Set(), windowMs, threshold = SEM.threshold, lexical = () => null, log = null }) {
  const n = items.length
  const vec = items.map((it) => vectorOf(it.article))
  if (vec.filter(Boolean).length < 2) return []
  const ents = items.map((it, i) => (vec[i] ? entitiesOf(it.article.headline, terms, ignore) : null))
  const gid = new Array(n)
  groups.forEach((g, k) => g.forEach((i) => { gid[i] = k }))
  const pairs = new Map() // i * n + j (i < j) -> detail, only for embedded pairs in different groups and inside the window
  for (let i = 0; i < n; i++) {
    if (!vec[i]) continue
    for (let j = i + 1; j < n; j++) {
      if (!vec[j] || gid[i] === gid[j]) continue
      const dt = Math.abs(items[i].tMs - items[j].tMs)
      if (dt > windowMs) continue
      const cos = cosine(vec[i], vec[j]), entity = entitySimilarity(ents[i], ents[j])
      pairs.set(i * n + j, { i, j, cos, entity, dtHours: dt / HOUR, score: pairScore(cos, entity, dt) })
    }
  }
  if (!pairs.size) return []
  const pairOf = (i, j) => pairs.get(i < j ? i * n + j : j * n + i)
  const link = (A, B) => { // average over embedded cross pairs; out-of-window pairs count as 0
    let sum = 0, count = 0, best = null
    for (const i of A) for (const j of B) {
      if (!vec[i] || !vec[j]) continue
      count++
      const p = pairOf(i, j)
      if (p) { sum += p.score; if (!best || p.score > best.score) best = p }
    }
    return { mean: count ? sum / count : -1, best }
  }
  const describe = (best) => ({
    a: items[best.i].article.headline, b: items[best.j].article.headline,
    lexical: lexical(best.i, best.j), cosine: +best.cos.toFixed(3), entity: best.entity == null ? null : +best.entity.toFixed(3),
    dtHours: +best.dtHours.toFixed(1), pairScore: +best.score.toFixed(3)
  })
  const cur = groups.map((g) => g.slice())
  const merges = []
  for (;;) {
    let top = null
    for (let a = 0; a < cur.length; a++) for (let b = a + 1; b < cur.length; b++) {
      if (!cur[a].length || !cur[b].length) continue
      const { mean, best } = link(cur[a], cur[b])
      if (mean >= threshold && (!top || mean > top.mean)) top = { a, b, mean, best }
    }
    if (!top) break
    const members = [...cur[top.a], ...cur[top.b]]
    merges.push({ members, score: top.mean })
    log?.push({ type: 'semantic-merge', score: +top.mean.toFixed(3), threshold, ...describe(top.best), size: members.length })
    cur[top.a] = members
    cur[top.b] = []
  }
  if (log) { // the close calls, for tuning: group pairs that fell just short
    const floor = threshold - SEM.near_miss_margin
    for (let a = 0; a < cur.length; a++) for (let b = a + 1; b < cur.length; b++) {
      if (!cur[a].length || !cur[b].length) continue
      const { mean, best } = link(cur[a], cur[b])
      if (best && mean >= floor && mean < threshold) log.push({ type: 'near-miss', score: +mean.toFixed(3), threshold, ...describe(best) })
    }
  }
  return merges
}
