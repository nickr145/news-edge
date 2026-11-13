// Builds data/news_background.json: headline words that are ordinary vocabulary across many tickers' news
// ("ai", "price", "ceo", "earnings"...). The storyline detector never treats these as a story, however often
// they repeat. Run when you want to refresh it (needs network); then run scripts/sync_news_profiles.py.
//
//   node scripts/build_background_tokens.mjs
import { readFileSync, writeFileSync } from 'node:fs'
import { headlineTokens } from '../frontend/src/lib/local/tokens.js'

const profiles = JSON.parse(readFileSync('data/news_profiles.json', 'utf8'))
const PER_SECTOR = 2, MIN_TICKER_SHARE = 0.12

// two tickers per sector, so the sample spans industries rather than one sector's vocabulary
const bySector = {}
for (const [sym, t] of Object.entries(profiles.tickers)) (bySector[t.sector] ||= []).push(sym)
const sample = Object.values(bySector).flatMap((syms) => syms.slice(0, PER_SECTOR))

const present = new Map() // token -> number of sampled tickers whose news uses it in >= 2 headlines
let used = 0
for (const sym of sample) {
  try {
    const url = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(sym.replace('.', '-'))}&newsCount=50&quotesCount=0`
    const res = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0' } })
    const titles = ((await res.json()).news || []).map((n) => n.title).filter(Boolean)
    if (titles.length < 10) continue
    const counts = new Map()
    for (const title of titles) for (const tok of headlineTokens(title)) counts.set(tok, (counts.get(tok) || 0) + 1)
    for (const [tok, c] of counts) if (c >= 2) present.set(tok, (present.get(tok) || 0) + 1)
    used++
  } catch { /* skip */ }
}

// never exclude the people the profiles track: a leadership story must stay detectable
const people = new Set(Object.values(profiles.tickers).flatMap((t) => (t.people || []).flatMap((p) => [...headlineTokens(p)])))
const tokens = [...present].filter(([tok, n]) => n / used >= MIN_TICKER_SHARE && !people.has(tok)).map(([tok]) => tok).sort()
writeFileSync('data/news_background.json', JSON.stringify({ version: 1, tickers_sampled: used, min_ticker_share: MIN_TICKER_SHARE, tokens }, null, 0))
console.log(`sampled ${used} tickers -> ${tokens.length} background tokens`)
console.log(tokens.slice(0, 120).join(' '))
