// Event grouping + relationship-aware relevance for news. Mirrored by ios/NewsEdge/.../NewsEvents.swift;
// both load the same curated data (data/news_profiles.json, synced by scripts/sync_news_profiles.py).
import profiles from '../../data/newsProfiles.json'
import * as A from './analytics'

const HOUR = 3_600_000
export const EVENT_WINDOW_MS = 48 * HOUR
const GENERIC_FIRST_WORDS = new Set(['general', 'united', 'american', 'first', 'national', 'international', 'global', 'southern', 'western', 'eastern', 'northern', 'pacific', 'great', 'new', 'bank'])
const SUFFIXES = /\b(inc|corp|corporation|co|company|ltd|plc|holdings|group|incorporated|class [a-c]|the)\b\.?/g

/** Whole-term match (term bounded by non-alphanumerics), no regex so Swift can mirror it exactly. */
export function hasTerm(text, term) {
  let i = text.indexOf(term)
  while (i !== -1) {
    const before = i === 0 ? '' : text[i - 1], after = text[i + term.length] ?? ''
    if (!/[a-z0-9]/.test(before) && !/[a-z0-9]/.test(after)) return true
    i = text.indexOf(term, i + 1)
  }
  return false
}

const cleanName = (name) => name.toLowerCase().replace(/&/g, ' and ').replace(SUFFIXES, ' ').replace(/[.,]/g, ' ').replace(/\s+/g, ' ').trim()

/** Everything we know about how news relates to `ticker` (curated overrides + sector template + catalog name). */
export function profileFor(ticker, companyName = null) {
  const sym = String(ticker).toUpperCase()
  const t = profiles.tickers[sym] || {}
  const sector = profiles.sectors[t.sector] || null
  const aliases = new Set((t.aliases || []).map((a) => a.toLowerCase()))
  if (companyName) {
    const full = cleanName(companyName)
    if (full) aliases.add(full)
    const first = full.split(' ')[0]
    if (first && first.length >= 5 && !GENERIC_FIRST_WORDS.has(first)) aliases.add(first)
  }
  return {
    ticker: sym,
    aliases: [...aliases],
    people: (t.people || []).map((x) => x.toLowerCase()),
    supply: [...(t.supply || []), ...(sector?.supply_terms || [])].map((x) => x.toLowerCase()),
    competitors: (t.competitors || []).map((x) => x.toLowerCase()),
    sectorTerms: (sector?.sector_terms || []).map((x) => x.toLowerCase()),
    macro: (sector?.macro_terms || []).map((x) => x.toLowerCase()),
    inverse: (sector?.inverse_terms || []).map((x) => x.toLowerCase()),
    sectorLabel: sector?.label || null
  }
}

const CH = profiles.channels
const DIRECT_MIN = 0.35 // the default minimum relevance

/**
 * How a headline bears on `ticker`: direct (names the company/ticker) or one of the indirect channels
 * (leadership, supply chain, sector, competitor, macro) with a sign that maps the headline's text
 * sentiment onto the ticker (+1 same direction, -1 inverse, e.g. a competitor's bad news).
 * Returns null if it bears on the ticker in no way we recognise.
 */
export function exposureOf(profile, headline, symbols = []) {
  const h = String(headline || '').toLowerCase()
  const direct = A.relevance(profile.ticker, headline, symbols, profile.aliases)
  // A headline that is both tagged with the ticker and names the company (0.85+) counts in full; tag-only or
  // mention-only articles (e.g. Yahoo tagging a retirement story with five tickers) count proportionally less.
  const directWeight = Math.min(1, direct / 0.8)
  let best = direct > 0 ? { channel: 'direct', relevance: direct, weight: directWeight, sign: 1 } : null
  // Naming the company (or being tagged with its ticker) is direct news, whatever else the headline also touches.
  if (direct >= DIRECT_MIN) return best
  const consider = (channel, terms, sign = CH[channel].sign) => {
    if (!terms.some((t) => hasTerm(h, t))) return
    const relevance = CH[channel].relevance
    if (!best || relevance > best.relevance) best = { channel, relevance, weight: CH[channel].weight, sign }
  }
  consider('people', profile.people)
  consider('supply', profile.supply)
  consider('sector', profile.sectorTerms)
  consider('competitor', profile.competitors)
  consider('macro', profile.macro)
  consider('macro', profile.inverse, -CH.macro.sign)
  return best
}

// ---- headline tokens -------------------------------------------------------
const STOP = new Set(('a an the and or but of to in on at for from by with as is are was were be been it its this that these those will would could may might can '
  + 'after before amid over under into than then so not no new says say said report reports reported reportedly news update updates today week here why how what who when '
  + 'stock stocks share shares investors investor market markets wall street analyst analysts vs per via more most').split(' '))

const stem = (w) => {
  if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3)
  if (w.length > 4 && w.endsWith('ed')) return w.slice(0, -2)
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1)
  return w
}

/** Informative tokens of a headline: publisher suffix, filler words and the company's own names removed. */
export function headlineTokens(headline, ignore = new Set()) {
  const base = String(headline || '').replace(/\s*[-–|]\s*[A-Za-z][\w\s.&]{1,40}$/, '').toLowerCase()
    .replace(/(?<=\d),(?=\d{3})/g, '').replace(/['’]s\b/g, '')
  const out = new Set()
  for (const raw of base.match(/[a-z0-9]+(?:\.\d+)?/g) || []) {
    if (STOP.has(raw)) continue
    const w = stem(raw)
    if (w.length < 2 || STOP.has(w) || ignore.has(w)) continue
    out.add(w)
  }
  return out
}

/** Words belonging to the company itself (every headline has them, so they say nothing about *which* event). */
export function ignoreTokens(profile) {
  const out = new Set([profile.ticker.toLowerCase()])
  for (const a of profile.aliases) for (const w of a.match(/[a-z0-9]+/g) || []) out.add(stem(w))
  return out
}

/** Same event if the headlines share most of their informative words (rewrites and syndication). */
export function sameEvent(a, b) {
  let inter = 0
  for (const t of a) if (b.has(t)) inter++
  if (inter >= 1 && inter === a.size && inter === b.size) return true // identical informative words, however few
  if (inter < 2) return false
  const jaccard = inter / (a.size + b.size - inter)
  const overlap = inter / Math.min(a.size, b.size)
  return jaccard >= 0.5 || (overlap >= 0.75 && inter >= 3)
}

/** One event's weight: 1 for a single outlet, +0.5*ln(outlets) beyond that, capped (echo != importance, breadth != nothing). */
export const coverageBoost = (outlets) => Math.min(2.5, 1 + 0.5 * Math.log(Math.max(outlets, 1)))

/**
 * Groups exposed articles into events. `items`: { article, exposure, tMs, value } where value already includes
 * the sentiment sign/source weight. Returns events newest first.
 */
export function groupEvents(items, ignore) {
  const toks = items.map((it) => headlineTokens(it.article.headline, ignore))
  const parent = items.map((_, i) => i)
  const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])))
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      if (Math.abs(items[i].tMs - items[j].tMs) <= EVENT_WINDOW_MS && sameEvent(toks[i], toks[j])) parent[find(i)] = find(j)
    }
  }
  const groups = new Map()
  items.forEach((it, i) => groups.set(find(i), [...(groups.get(find(i)) || []), it]))
  return [...groups.values()].map((members) => {
    const wSum = members.reduce((a, m) => a + m.exposure.weight, 0)
    const outlets = new Set(members.map((m) => A.normalize(m.article.source || '') || String(m.article.id))).size
    // representative: trusted outlet first, then newest
    const rep = [...members].sort((x, y) => (y.article.source_weight ?? 1) - (x.article.source_weight ?? 1) || y.tMs - x.tMs)[0]
    const top = members.reduce((a, m) => (m.exposure.weight > a.exposure.weight ? m : a), members[0])
    return {
      id: rep.article.id,
      articles: members.map((m) => m.article),
      size: members.length,
      outlets,
      value: members.reduce((a, m) => a + m.exposure.weight * m.value, 0) / wSum,
      weight: top.exposure.weight * coverageBoost(outlets),
      tMs: Math.min(...members.map((m) => m.tMs)),
      latestMs: Math.max(...members.map((m) => m.tMs)),
      channel: top.exposure.channel,
      relevance: Math.max(...members.map((m) => m.exposure.relevance)),
      rep: rep.article
    }
  }).sort((a, b) => b.latestMs - a.latestMs)
}

// ---- searches that find the indirect news ----------------------------------
const orQuery = (terms, n) => terms.slice(0, n).map((t) => (/\s/.test(t) ? `"${t}"` : t)).join(' OR ')

/** Google News queries per channel for a ticker (people/supply/sector/macro); results are kept only if exposureOf recognises them. */
export function indirectQueries(profile) {
  const lead = profile.aliases[0]
  const qs = []
  if (lead) qs.push(orQuery([`${lead} ceo`, `${lead} chief executive`, `${lead} cfo`, ...profile.people], 5))
  if (profile.supply.length) qs.push(orQuery(profile.supply, 6))
  if (profile.sectorTerms.length) qs.push(orQuery(profile.sectorTerms, 4))
  if (profile.macro.length) qs.push(orQuery(profile.macro, 4))
  return qs.map((q) => `${q} when:7d`)
}
