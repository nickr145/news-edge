# Semantic Indirect Relevance (Phase 4, web) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rescue headlines that bear on a ticker but match none of its profile keywords, by comparing their embeddings to per-channel anchor sentences built from the profile (web, shadow mode first).

**Architecture:** A new pure module `indirect.js` builds anchor texts from a profile and scores a headline vector against anchor vectors. `client.js` keeps Google search results that `exposureOf` rejects as unadmitted `cand` articles, embeds anchors and candidates in the background (never blocking the feed), and in `eventsFor` admits a candidate only when no keyword matched and the embedding score clears `indirect.semantic.threshold` and `margin`. `mode` is `off | shadow | on`; shadow logs to `debug.decisions` and changes nothing.

**Tech Stack:** JavaScript (ESM), vitest, existing MiniLM embedder (`embeddings.js`), `data/news_config.json` synced to web and iOS by `scripts/sync_news_profiles.py`.

Spec: `docs/superpowers/specs/2026-11-19-semantic-indirect-relevance-design.md`. iOS (Phase 4b) gets its own plan once this lands.

## Global Constraints

- Recall only. A keyword match from `exposureOf` is never overridden. No change to the channel relevance, weight or sign table (`data/news_profiles.json` `channels`).
- Candidates are never shown or counted unless admitted. Embedding never delays the feed: anchors and candidates are embedded in the background, like articles today.
- `indirect.semantic.mode` is `off`, `shadow` (default) or `on`. `threshold` and `margin` ship as `null` until Task 5 sets them from live data; while `threshold` is `null` the feature is inactive (no candidates stored, no anchors embedded).
- Commits in this repo carry no Co-Authored-By trailer (user preference).
- Run tests from `/Users/nrebello/Documents/NewsEdge/frontend`. Baseline: `npx vitest run` shows 94 passed, 2 skipped.
- Sync data copies from the repo root: `python3 scripts/sync_news_profiles.py`.

## File Structure

- Create `frontend/src/lib/local/indirect.js`: `anchorTexts(profile)`, `semanticExposure(vec, anchors, opts)`. Pure, no I/O.
- Create `frontend/src/lib/local/indirect.test.js`: unit tests for both.
- Create `frontend/src/lib/local/indirect.shadow.test.js`: live evaluation harness (skipped unless `SHADOW=1`).
- Modify `frontend/src/lib/local/client.js`: candidate retention, anchor cache, admission and decision log.
- Modify `frontend/src/lib/local/client.test.js`: client-level tests with a fake embedder.
- Modify `data/news_config.json` (and the synced copies `frontend/src/data/newsConfig.json`, `ios/NewsEdge/NewsEdge/Resources/NewsConfig.json`): add the `indirect` block.
- Modify `README.md`: document the stage and the evaluation result.

---

### Task 1: Config block and the pure `indirect.js` module

**Files:**
- Modify: `data/news_config.json` (insert between the `storylines` and `embedding` blocks)
- Create: `frontend/src/lib/local/indirect.js`
- Test: `frontend/src/lib/local/indirect.test.js`

**Interfaces:**
- Consumes: `profileFor(ticker, name)` from `./news` (profile shape: `aliases`, `people`, `supply`, `competitors`, `sectorTerms`, `macro`, `sectorLabel`, `ticker`); `cosine(a, b)` from `./embeddings`; `channels` table from `../../data/newsProfiles.json`.
- Produces:
  - `anchorTexts(profile) -> Array<{ channel: 'people'|'supply'|'sector'|'competitor'|'macro', text: string }>`
  - `semanticExposure(vec, anchors, { threshold, margin }) -> null | { channel, cosine, margin, admit, exposure }` where `anchors` is `Array<{ channel, vec }>` and `exposure = { channel, relevance, weight, sign, embedded: true }`. Returns `null` only when `anchors` is empty. `margin` in the result is best channel cosine minus runner-up channel cosine (runner-up is 0 when only one channel has anchors).

- [ ] **Step 1: Write the failing test**

Create `frontend/src/lib/local/indirect.test.js`:

```js
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run indirect.test`
Expected: FAIL (`Failed to resolve import "./indirect"`).

- [ ] **Step 3: Add the config block**

In `data/news_config.json`, between the closing `},` of the `storylines` object and `"embedding": {`, insert:

```json
  "indirect": {
    "semantic": {
      "mode": "shadow",
      "threshold": null,
      "margin": null,
      "near_miss": 0.05
    }
  },
```

Then from the repo root run `python3 scripts/sync_news_profiles.py` (expected: `synced 7 copies (2 were stale)`) and `python3 scripts/sync_news_profiles.py --check` (expected: no output, exit 0).

- [ ] **Step 4: Write the implementation**

Create `frontend/src/lib/local/indirect.js`:

```js
// Semantic indirect relevance: decides whether a headline that matches none of a ticker's profile keywords still bears
// on it, by comparing its embedding to anchor sentences built from the profile (one set per indirect channel). Pure
// functions; client.js owns embedding, caching and the mode switch. Keyword matches (news.js exposureOf) always win.
import profiles from '../../data/newsProfiles.json'
import { cosine } from './embeddings'

const CH = profiles.channels
const TERMS_PER_ANCHOR = 3
const ANCHORS_PER_CHANNEL = 2

// Reviewable on purpose: the wording decides what "close to this channel" means. Edit here, the cache key changes with it.
const TEMPLATES = {
  people: (co, _label, terms) => `${co} leadership and executives: ${terms}`,
  supply: (co, _label, terms) => `${co} suppliers, customers and supply chain: ${terms}`,
  sector: (_co, label, terms) => `${label} industry and sector news: ${terms}`,
  competitor: (co, _label, terms) => `${co} competitors and rivals: ${terms}`,
  macro: (_co, label, terms) => `${label} policy, regulation, trade and economy: ${terms}`
}

/** Anchor sentences per indirect channel, from the first TERMS_PER_ANCHOR * ANCHORS_PER_CHANNEL profile terms of each. */
export function anchorTexts(profile) {
  const co = profile.aliases[0] || profile.ticker.toLowerCase()
  const label = (profile.sectorLabel || co).toLowerCase()
  const byChannel = { people: profile.people, supply: profile.supply, sector: profile.sectorTerms, competitor: profile.competitors, macro: profile.macro }
  const out = []
  for (const [channel, list] of Object.entries(byChannel)) {
    const all = [...new Set(list)]
    const terms = all.filter((t) => !all.some((o) => o !== t && o.includes(t))) // "huang" adds nothing next to "jensen huang"
    for (let i = 0; i < terms.length && i < TERMS_PER_ANCHOR * ANCHORS_PER_CHANNEL; i += TERMS_PER_ANCHOR) {
      out.push({ channel, text: TEMPLATES[channel](co, label, terms.slice(i, i + TERMS_PER_ANCHOR).join(', ')) })
    }
  }
  return out
}

/**
 * Scores `vec` against `anchors` ([{channel, vec}]). A channel's score is its best anchor's cosine. `admit` needs the
 * best channel >= threshold AND ahead of the runner-up channel by >= margin (so a headline torn between "supplier" and
 * "sector" is left out). With one channel only, the runner-up counts as 0.
 */
export function semanticExposure(vec, anchors, { threshold, margin }) {
  const best = {}
  for (const a of anchors) best[a.channel] = Math.max(best[a.channel] ?? -1, cosine(vec, a.vec))
  const ranked = Object.entries(best).sort((x, y) => y[1] - x[1])
  if (!ranked.length) return null
  const [channel, cos] = ranked[0]
  const gap = cos - (ranked[1]?.[1] ?? 0)
  const { relevance, weight, sign } = CH[channel]
  return { channel, cosine: cos, margin: gap, admit: cos >= threshold && gap >= margin, exposure: { channel, relevance, weight, sign, embedded: true } }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run`
Expected: all pass (94 + the new indirect tests, 2 skipped).

- [ ] **Step 6: Commit**

```bash
cd /Users/nrebello/Documents/NewsEdge
git add data/news_config.json frontend/src/data/newsConfig.json ios/NewsEdge/NewsEdge/Resources/NewsConfig.json frontend/src/lib/local/indirect.js frontend/src/lib/local/indirect.test.js
git commit -m "Phase 4: anchors and semantic exposure scoring (indirect.js), config block"
```

---

### Task 2: Keep rejected search results as candidates

**Files:**
- Modify: `frontend/src/lib/local/client.js` (options, `articles()`, `withoutEmb`)
- Test: `frontend/src/lib/local/client.test.js` (append a new `describe`)

**Interfaces:**
- Consumes: nothing new from earlier tasks except the config block (`config.indirect.semantic`).
- Produces: `createLocalApi` options `indirectMode` (`'off'|'shadow'|'on'`), `indirectThreshold`, `indirectMargin`, `maxCandidates` (default 200). Cached articles may now carry `cand: true`. Inside `createLocalApi`, the constants `iMode`, `iThreshold`, `iMargin`, `indirectActive` (used by Tasks 3 and 4).

- [ ] **Step 1: Write the failing tests**

Append to `frontend/src/lib/local/client.test.js` (after the `indirect news` describe; reuse the file's `make`, `search`, `NOW`, `H`):

```js
// ---- indirect candidates: rejected search results kept for the semantic check ---------
describe('indirect candidates', () => {
  const rssItem = (title, source, time) => `<item><title>${title} - ${source}</title><link>https://g.test/${encodeURIComponent(title)}</link><pubDate>${time.toUTCString()}</pubDate><source url="x">${source}</source></item>`
  const MISS = 'Earthquake shuts down island plants that make advanced processors' // no profile keyword in it
  const gsearchRSS = `<rss><channel>${[
    rssItem('TSMC warns of capacity shortage', 'Reuters', new Date(NOW.getTime() - 2 * H)),
    rssItem(MISS, 'Reuters', new Date(NOW.getTime() - 3 * H)),
    rssItem('Local bakery wins award', 'Gazette', new Date(NOW.getTime() - H))
  ].join('')}</channel></rss>`
  const direct = search([{ title: 'Nvidia posts record data center revenue', time: new Date(NOW.getTime() - H), tickers: ['NVDA'] }])
  const setup = (extra = {}) => make({ search: { body: direct }, gnews: 'down', gsearch: { body: gsearchRSS } },
    { companyName: () => 'NVIDIA Corporation', indirectThreshold: 0.6, indirectMargin: 0.2, ...extra })
  const cached = (storage) => JSON.parse(storage.getItem('newsedge_news_v1_NVDA'))

  it('keeps rejected search results flagged cand, and the keyword-accepted one unflagged', async () => {
    const { api, storage } = setup({ indirectMode: 'shadow' })
    await api.get('/api/news/NVDA', { params: { days: 30 } })
    expect(cached(storage).filter((a) => a.cand).map((a) => a.headline).sort()).toEqual(['Earthquake shuts down island plants that make advanced processors', 'Local bakery wins award'])
    expect(cached(storage).find((a) => a.headline.startsWith('TSMC')).cand).toBeUndefined()
  })
  it('never counts a candidate in the feed', async () => {
    const { api } = setup({ indirectMode: 'shadow' })
    const { data } = await api.get('/api/news/NVDA', { params: { days: 30, min_relevance: 0.2 } })
    expect(data.map((a) => a.headline).sort()).toEqual(['Nvidia posts record data center revenue', 'TSMC warns of capacity shortage'])
  })
  it('keeps no candidates when the mode is off, or while the threshold is unset', async () => {
    for (const extra of [{ indirectMode: 'off' }, { indirectMode: 'shadow', indirectThreshold: null }]) {
      const { api, storage } = setup(extra)
      await api.get('/api/news/NVDA', { params: { days: 30 } })
      expect(cached(storage).some((a) => a.cand)).toBe(false)
    }
  })
  it('keeps only the newest maxCandidates candidates', async () => {
    const { api, storage } = setup({ indirectMode: 'shadow', maxCandidates: 1 })
    await api.get('/api/news/NVDA', { params: { days: 30 } })
    expect(cached(storage).filter((a) => a.cand).map((a) => a.headline)).toEqual(['Local bakery wins award']) // newest of the two
  })
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run client.test -t "indirect candidates"`
Expected: FAIL (first and fourth tests: no `cand` articles stored; the others may pass already).

- [ ] **Step 3: Implement**

In `frontend/src/lib/local/client.js`:

(a) Add to the options destructuring, after `storylineSimilarity // ...`:

```js
  storylineSimilarity, // default: storylines.semantic.similarity (only evaluation overrides it)
  indirectMode, // 'off' | 'shadow' | 'on'; default: indirect.semantic.mode
  indirectThreshold, // default: indirect.semantic.threshold (null = feature inactive)
  indirectMargin, // default: indirect.semantic.margin
  maxCandidates = 200 // unadmitted indirect candidates kept per ticker (newest first)
```
(the existing `storylineSimilarity` line loses its trailing comment-only form: it becomes `storylineSimilarity, // ...` as shown).

(b) Right after `const src = createSources({ fetchImpl, storage })` add:

```js
  const ISEM = config.indirect.semantic
  const iMode = indirectMode ?? ISEM.mode
  const iThreshold = indirectThreshold === undefined ? ISEM.threshold : indirectThreshold
  const iMargin = indirectMargin ?? ISEM.margin ?? 0
  const indirectActive = iMode !== 'off' && iThreshold != null // no threshold yet = nothing to compare against
```

(c) In `articles()`, replace the block

```js
      if (!indirectDone.has(sym)) {
        indirectDone.add(sym)
        const profile = profileOf(ticker)
        const found = (await Promise.all(N.indirectQueries(profile).map((q) => src.googleSearch(q).catch(() => [])))).flat()
        fresh = fresh.concat(found.filter((a) => N.exposureOf(profile, a.headline, a.symbols || [])))
      }
```
with
```js
      let candidates = []
      if (!indirectDone.has(sym)) {
        indirectDone.add(sym)
        const profile = profileOf(ticker)
        const found = (await Promise.all(N.indirectQueries(profile).map((q) => src.googleSearch(q).catch(() => [])))).flat()
        const bears = (a) => N.exposureOf(profile, a.headline, a.symbols || [])
        fresh = fresh.concat(found.filter(bears))
        // Rejected results are kept, flagged, for the semantic check (indirect.js); they count only if admitted.
        if (indirectActive) candidates = found.filter((a) => !bears(a)).map((a) => ({ ...a, cand: true }))
      }
```

(d) Replace `for (const a of fresh) {` with `for (const a of [...fresh, ...candidates]) {` (candidates after `fresh`, so an article that is both stays unflagged).

(e) Replace the `merged` line with:

```js
      let room = maxCandidates
      const merged = [...byId.values()].filter((a) => Date.parse(a.published_at) >= cutoff).sort((a, b) => b.published_at.localeCompare(a.published_at))
        .filter((a) => !a.cand || room-- > 0)
```

(f) Replace `const withoutEmb = ({ emb, ...rest }) => rest // embeddings stay in the cache, never in what the UI receives` with:

```js
  const withoutEmb = ({ emb, cand, ...rest }) => rest // embeddings and the candidate flag stay in the cache, never in what the UI receives
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run`
Expected: all pass (existing 94 unchanged, since the default threshold is `null`).

- [ ] **Step 5: Commit**

```bash
cd /Users/nrebello/Documents/NewsEdge
git add frontend/src/lib/local/client.js frontend/src/lib/local/client.test.js
git commit -m "Phase 4: keep rejected indirect search results as unadmitted candidates"
```

---

### Task 3: Embed and cache anchors in the background

**Files:**
- Modify: `frontend/src/lib/local/client.js` (imports, `embedMissing`, new `ensureAnchors`)
- Test: `frontend/src/lib/local/client.test.js` (extend the `indirect candidates` describe)

**Interfaces:**
- Consumes: `anchorTexts(profile)` (Task 1); `iMode`, `iThreshold`, `indirectActive` (Task 2); `quantize`/`dequantize` from `./embeddings`.
- Produces: in-memory `anchorsReady: Map<symbol, Array<{ channel, vec }>>` (read in Task 4); storage key `newsedge_anchors_v1_<SYMBOL>` holding `{ key, embs }` where `key = JSON.stringify([model, texts])` and `embs` is the quantized vectors in anchor order.

- [ ] **Step 1: Write the failing tests**

Add `vi` is already imported at the top of `client.test.js`. Inside the `indirect candidates` describe, after `cached`, add the fake embedder and these tests:

```js
  // 5 axes: people, supply, sector, competitor, macro. Anchor text picks its axis; MISS is "supplier-ish"; everything else is the zero vector.
  const AXIS = [/leadership and executives/, /suppliers, customers and supply chain/, /industry and sector news/, /competitors and rivals/, /policy, regulation, trade and economy/]
  const vecOf = (t) => {
    const i = AXIS.findIndex((re) => re.test(t))
    if (i >= 0) return Array.from({ length: 5 }, (_, k) => (k === i ? 1 : 0))
    return t.includes('Earthquake') ? [0, 0.9, 0.2, 0, 0] : [0, 0, 0, 0, 0]
  }
  const fakeEmbedder = () => ({ embed: vi.fn(async (texts) => texts.map(vecOf)) })
  const anchorItem = (storage) => JSON.parse(storage.getItem('newsedge_anchors_v1_NVDA') || 'null')

  it('embeds the anchors once and caches them by text and model', async () => {
    const embedder = fakeEmbedder()
    const { api, storage } = setup({ indirectMode: 'shadow', embedder })
    await api.get('/api/news/NVDA', { params: { days: 30 } })
    await vi.waitFor(() => expect(anchorItem(storage)).not.toBeNull())
    const a = anchorItem(storage)
    expect(a.embs.length).toBeGreaterThanOrEqual(5)
    expect(JSON.parse(a.key)[1].some((t) => t.includes('suppliers, customers and supply chain'))).toBe(true)

    const again = fakeEmbedder() // a new session on the same storage must not re-embed the anchors
    const second = createLocalApi({ fetchImpl: net({ search: { body: direct }, gnews: 'down', gsearch: { body: gsearchRSS } }), storage, score, companyName: () => 'NVIDIA Corporation', now: () => NOW,
      indirectMode: 'shadow', indirectThreshold: 0.6, indirectMargin: 0.2, embedder: again })
    await second.get('/api/news/NVDA', { params: { days: 30 } })
    await vi.waitFor(() => expect(cached(storage).every((x) => x.emb)).toBe(true))
    expect(again.embed.mock.calls.flat(2).some((t) => t.includes('suppliers, customers and supply chain'))).toBe(false)
  })
  it('does not embed anchors when the mode is off or the threshold is unset', async () => {
    for (const extra of [{ indirectMode: 'off' }, { indirectThreshold: null }]) {
      const { api, storage } = setup({ embedder: fakeEmbedder(), ...extra })
      await api.get('/api/news/NVDA', { params: { days: 30 } })
      await vi.waitFor(() => expect(cached(storage).every((x) => x.emb)).toBe(true))
      expect(anchorItem(storage)).toBeNull()
    }
  })
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run client.test -t "indirect candidates"`
Expected: FAIL (first new test times out waiting for the anchors item).

- [ ] **Step 3: Implement**

In `frontend/src/lib/local/client.js`:

(a) Change the imports:

```js
import { createEmbedder, dequantize, embeddingText, quantize } from './embeddings'
import { anchorTexts } from './indirect'
```

(b) Add before `let embedding = Promise.resolve()` (inside `createLocalApi`):

```js
  const anchorStoreKey = (t) => `newsedge_anchors_v1_${A.yahooSymbol(t)}`
  const anchorsReady = new Map() // symbol -> [{ channel, vec }]: indirect.js anchors with their vectors, once embedded

  /** Embeds a ticker's anchor sentences once ever (cached by text + model); a no-op while the feature is inactive. */
  async function ensureAnchors(ticker) {
    const sym = A.yahooSymbol(ticker)
    if (!indirectActive || anchorsReady.has(sym)) return
    const texts = anchorTexts(profileOf(ticker))
    if (!texts.length) return
    const key = JSON.stringify([config.embedding.model, texts.map((x) => x.text)])
    let stored = null
    try { stored = JSON.parse(storage.getItem(anchorStoreKey(ticker)) || 'null') } catch { /* unreadable: re-embed */ }
    let embs = stored?.key === key ? stored.embs : null
    if (!embs) {
      const vecs = await embedder.embed(texts.map((x) => x.text))
      if (!vecs) return // model unavailable: try again on the next pass
      embs = vecs.map(quantize)
      try { storage.setItem(anchorStoreKey(ticker), JSON.stringify({ key, embs })) } catch { /* quota */ }
    }
    anchorsReady.set(sym, texts.map((x, i) => ({ channel: x.channel, vec: dequantize(embs[i]) })))
  }
```
`profileOf` is declared later with `const`; it is only called at run time, after initialisation, so the order is fine.

(c) In `embedMissing`, make the first line of the chained async function:

```js
    embedding = embedding.then(async () => {
      await ensureAnchors(ticker).catch(() => {}) // anchors first, but never let them block the articles
      const todo = loadNews(ticker).filter((a) => !a.emb)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/nrebello/Documents/NewsEdge
git add frontend/src/lib/local/client.js frontend/src/lib/local/client.test.js
git commit -m "Phase 4: embed and cache indirect anchors in the background"
```

---

### Task 4: Admit candidates in `eventsFor` (shadow logs, on applies)

**Files:**
- Modify: `frontend/src/lib/local/client.js` (imports, `eventsFor`)
- Test: `frontend/src/lib/local/client.test.js` (extend the `indirect candidates` describe)

**Interfaces:**
- Consumes: `semanticExposure` (Task 1), `vectorOf` from `./semantic`, `anchorsReady`, `iMode`, `iThreshold`, `iMargin`, `indirectActive` (Tasks 2-3), `ISEM.near_miss` from config.
- Produces: decision-log entries `{ type: 'semantic-indirect', applied, mode, headline, channel, cosine, margin, relevance }`, returned by `api.debug.decisions(ticker)`. In `on` mode an admitted candidate becomes a normal event with `channel` set to the winning channel.

- [ ] **Step 1: Write the failing tests**

Inside the `indirect candidates` describe, after the Task 3 tests, add:

```js
  const settle = (storage) => vi.waitFor(() => {
    expect(anchorItem(storage)).not.toBeNull()
    expect(cached(storage).every((x) => x.emb)).toBe(true)
  })
  const feed = async (api, min = 0.2) => (await api.get('/api/news/NVDA', { params: { days: 30, min_relevance: min } })).data
  const run = async (extra, min) => {
    const { api, storage } = setup({ embedder: fakeEmbedder(), ...extra })
    await feed(api, min) // first pass: nothing embedded yet, so it is keyword-only
    await settle(storage)
    return { api, data: await feed(api, min) }
  }

  it('on: admits the candidate under the winning channel, and still leaves the unrelated one out', async () => {
    const { data } = await run({ indirectMode: 'on' })
    const hit = data.find((a) => a.headline === MISS)
    expect(hit).toMatchObject({ channel: 'supply', relevance_score: 0.5 })
    expect(hit.cand).toBeUndefined()
    expect(data.some((a) => /bakery/.test(a.headline))).toBe(false)
  })
  it('on: the relevance selector still applies to an admitted candidate', async () => {
    const { data } = await run({ indirectMode: 'on' }, 0.7) // supply relevance is 0.5
    expect(data.some((a) => a.headline === MISS)).toBe(false)
  })
  it('shadow: logs the admission but changes nothing', async () => {
    const { api, data } = await run({ indirectMode: 'shadow' })
    expect(data.some((a) => a.headline === MISS)).toBe(false)
    const entry = api.debug.decisions('NVDA').find((d) => d.type === 'semantic-indirect')
    expect(entry).toMatchObject({ applied: false, mode: 'shadow', headline: MISS, channel: 'supply', relevance: 0.5 })
    expect(entry.cosine).toBeGreaterThan(0.9)
    expect(api.debug.decisions('NVDA').filter((d) => d.type === 'semantic-indirect')).toHaveLength(1) // the bakery scores 0: not even a near miss
  })
  it('a keyword match is never overridden or logged', async () => {
    const { api, data } = await run({ indirectMode: 'on' })
    expect(data.find((a) => a.headline.startsWith('TSMC')).channel).toBe('supply') // by keyword, not embedding
    expect(api.debug.decisions('NVDA').some((d) => d.headline.startsWith('TSMC'))).toBe(false)
  })
  it('off: identical to today (no candidates, nothing logged)', async () => {
    const { api, data } = await run({ indirectMode: 'off' })
    expect(data.some((a) => a.headline === MISS)).toBe(false)
    expect(api.debug.decisions('NVDA').some((d) => d.type === 'semantic-indirect')).toBe(false)
  })
```
Note `run()` for `off` calls `settle`, which waits for anchors that are never stored in `off` mode. Change `settle` to take an `anchors = true` flag: `settle(storage, anchors = true)` and only check `anchorItem` when `anchors`; in `run`, pass `extra.indirectMode !== 'off'`. Write it that way:

```js
  const settle = (storage, anchors = true) => vi.waitFor(() => {
    if (anchors) expect(anchorItem(storage)).not.toBeNull()
    expect(cached(storage).every((x) => x.emb)).toBe(true)
  })
```
and in `run`: `await settle(storage, extra.indirectMode !== 'off')`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run client.test -t "indirect candidates"`
Expected: FAIL (`on` and `shadow` tests: no admission, no log entry).

- [ ] **Step 3: Implement**

In `frontend/src/lib/local/client.js`:

(a) Imports:

```js
import { anchorTexts, semanticExposure } from './indirect'
import { vectorOf } from './semantic'
```
(replacing the Task 3 `anchorTexts`-only import).

(b) In `eventsFor`, replace

```js
    for (const a of await articles(ticker)) {
      const tMs = Date.parse(a.published_at)
      if (tMs < contextMs) continue
      const exposure = N.exposureOf(profile, a.headline, a.symbols || [])
      if (!exposure || exposure.relevance < minRelevance) continue
      items.push({ article: a, exposure, tMs, value: a.compound * (a.source_weight ?? 1) * exposure.sign })
    }
    const log = [], ignore = N.ignoreTokens(profile)
```
with
```js
    const log = [], ignore = N.ignoreTokens(profile)
    const anchors = indirectActive ? anchorsReady.get(A.yahooSymbol(ticker)) : null
    const nearMiss = ISEM.near_miss ?? 0.05
    for (const a of await articles(ticker)) {
      const tMs = Date.parse(a.published_at)
      if (tMs < contextMs) continue
      let exposure = N.exposureOf(profile, a.headline, a.symbols || [])
      if (!exposure && a.cand && a.emb && anchors) { // no keyword matched: ask the embedding (keyword matches are never second-guessed)
        const r = semanticExposure(vectorOf(a), anchors, { threshold: iThreshold, margin: iMargin })
        if (r && r.cosine >= iThreshold - nearMiss) {
          const applied = r.admit && iMode === 'on'
          log.push({ type: 'semantic-indirect', applied, mode: iMode, headline: a.headline, channel: r.channel, cosine: round4(r.cosine), margin: round4(r.margin), relevance: r.exposure.relevance })
          if (applied) exposure = r.exposure
        }
      }
      if (!exposure || exposure.relevance < minRelevance) continue
      items.push({ article: a, exposure, tMs, value: a.compound * (a.source_weight ?? 1) * exposure.sign })
    }
```
`round4` is declared after `eventsFor` with `const`; it is only called at run time, so this is fine.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/nrebello/Documents/NewsEdge
git add frontend/src/lib/local/client.js frontend/src/lib/local/client.test.js
git commit -m "Phase 4: admit semantic indirect candidates (shadow logs, on applies)"
```

---

### Task 5: Live evaluation, set threshold and margin, document, open the PR

**Files:**
- Create: `frontend/src/lib/local/indirect.shadow.test.js`
- Modify: `data/news_config.json` (+ synced copies), `README.md`

**Interfaces:**
- Consumes: the `semantic-indirect` log entries (Task 4), `createLocalApi` options `indirectMode`, `indirectThreshold`, `indirectMargin`.
- Produces: concrete `indirect.semantic.threshold` / `margin` values in the config, mode left at `shadow`.

- [ ] **Step 1: Write the harness**

Create `frontend/src/lib/local/indirect.shadow.test.js`:

```js
// Shadow evaluation on LIVE news (needs network + the real model; skipped otherwise):
//   SHADOW=1 [SHADOW_TICKERS=NVDA,AAPL] [SHADOW_OUT=/path/report.json] npx vitest run indirect.shadow
// Runs every ticker with threshold 0 / margin 0 so each candidate's best channel, cosine and margin is logged, then writes
// them for offline sweeping (see the plan, Task 5) and hand-labelling of what a given threshold would admit.
import { describe, it } from 'vitest'
import { writeFileSync } from 'node:fs'
import handler from '../../../../api/proxy.mjs'
import { createLocalApi } from './client'
import { createEmbedder } from './embeddings'

const memStorage = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) } }
const viaProxy = async (url) => {
  const query = Object.fromEntries(new URL(url, 'http://x').searchParams)
  const res = { statusCode: 200, headers: {}, setHeader() {}, end(b) { this.body = b } }
  await handler({ query }, res)
  return { ok: res.statusCode < 300, status: res.statusCode, text: async () => String(res.body ?? '') }
}

describe.runIf(process.env.SHADOW)('semantic indirect relevance on live news', () => {
  it('logs every candidate with its best channel', async () => {
    const tickers = (process.env.SHADOW_TICKERS || 'AAPL,NVDA,TSLA,META,MSFT,AMZN,GOOGL,JPM,BA,INTC,PFE,XOM').split(',')
    const embedder = createEmbedder()
    const report = []
    for (const t of tickers) {
      const storage = memStorage()
      const api = createLocalApi({ fetchImpl: viaProxy, storage, embedder, indirectMode: 'shadow', indirectThreshold: 0, indirectMargin: 0 })
      const params = { days: 30, min_relevance: 0.2, limit: 1000 }
      const keyword = (await api.get(`/api/news/${t}`, { params })).data
      for (let i = 0; i < 120; i++) { // wait for the background embedding pass (anchors + articles)
        const a = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
        if (storage.getItem(`newsedge_anchors_v1_${t}`) && a.length && a.every((x) => x.emb)) break
        await new Promise((r) => setTimeout(r, 1000))
      }
      await api.get(`/api/news/${t}`, { params })
      const cached = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
      report.push({ ticker: t, articles: cached.length, candidates: cached.filter((a) => a.cand).length, keywordEvents: keyword.length,
        scored: api.debug.decisions(t).filter((e) => e.type === 'semantic-indirect') })
    }
    writeFileSync(process.env.SHADOW_OUT || '/tmp/indirect-shadow-report.json', JSON.stringify(report, null, 1))
  }, 1_200_000)
})
```

- [ ] **Step 2: Run it on live data**

Run (writes the report into the session scratchpad):

```bash
cd /Users/nrebello/Documents/NewsEdge/frontend
SHADOW=1 SHADOW_OUT=/private/tmp/claude-501/-Users-nrebello-Documents-NewsEdge/571cbb25-8a8f-488f-96b9-53fd8f50e98e/scratchpad/indirect-report.json npx vitest run indirect.shadow
```
Expected: 1 test passed (several minutes: model download, 12 tickers). If it fails with network errors, stop and tell the user rather than retrying.

- [ ] **Step 3: Sweep thresholds**

Run:

```bash
node -e '
const r = JSON.parse(require("fs").readFileSync(process.argv[1]));
console.log("candidates", r.reduce((n,t)=>n+t.candidates,0), "scored", r.reduce((n,t)=>n+t.scored.length,0));
for (const th of [0.4,0.45,0.5,0.55,0.6,0.65,0.7]) for (const m of [0,0.05,0.1]) {
  const hits = r.flatMap(t => t.scored.filter(e => e.cosine >= th && e.margin >= m));
  const by = {}; hits.forEach(e => by[e.channel] = (by[e.channel]||0)+1);
  console.log("th", th, "margin", m, "admitted", hits.length, JSON.stringify(by));
}' /private/tmp/claude-501/-Users-nrebello-Documents-NewsEdge/571cbb25-8a8f-488f-96b9-53fd8f50e98e/scratchpad/indirect-report.json
```
Expected: a table of admitted counts. Then print the candidate headlines for two or three promising settings (same filter, `console.log(t.ticker, e.channel, e.cosine, e.margin, e.headline)`) and label each as a genuine indirect hit or a false positive by reading the headline against the ticker. Pick the lowest threshold/margin where the false-positive share of admitted headlines is about 20% or less (the rate accepted for the storyline stage). If no setting gives usable precision, or the pool has almost no genuine misses, stop and report that to the user instead of picking values: that is the "known ceiling" case in the spec (broader queries would be the follow-up).

- [ ] **Step 4: Set the values**

In `data/news_config.json` set `indirect.semantic.threshold` and `margin` to the chosen numbers (mode stays `"shadow"`), then from the repo root:

```bash
python3 scripts/sync_news_profiles.py && python3 scripts/sync_news_profiles.py --check
```
Expected: `synced 7 copies (2 were stale)`, then no output.

- [ ] **Step 5: Document**

In `README.md`, after the paragraph beginning `**Semantic storylines (web and iOS).**`, add a paragraph in the same style:

```markdown
**Semantic indirect relevance (web).** The profile's keyword lists miss news that bears on a company without naming any of them ("an earthquake shuts island plants that make advanced processors"). Google search results that `exposureOf` rejects are kept as unadmitted *candidates* (`cand`, capped at 200 per ticker), embedded in the background, and compared with *anchor sentences* built from the profile per channel (`anchorTexts` in `indirect.js`, e.g. "nvidia suppliers, customers and supply chain: tsmc, sk hynix, hbm"). A candidate is admitted when its best channel's cosine is >= `indirect.semantic.threshold` (<T>) and it beats the runner-up channel by >= `margin` (<M>); it then gets that channel's normal relevance, weight and sign, so the relevance selector treats it like a keyword match. Keyword matches are never overridden. `indirect.semantic.mode` is `off`, `shadow` (default: logs `semantic-indirect` entries to `newsedge.api.debug.decisions`, changes nothing) or `on`. On 12 live tickers (<C> candidates) the chosen setting would admit <A> headlines, roughly <P>% of them genuine (<examples>). It only classifies what the four existing Google queries return. Reproduce with `SHADOW=1 npx vitest run indirect.shadow`.
```
Replace `<T>`, `<M>`, `<C>`, `<A>`, `<P>`, `<examples>` with the real values and two or three real example headlines from the sweep; the paragraph must not ship with angle-bracket markers.

- [ ] **Step 6: Verify everything**

```bash
cd /Users/nrebello/Documents/NewsEdge/frontend && npx vitest run
cd /Users/nrebello/Documents/NewsEdge && xcodebuild test -project ios/NewsEdge/NewsEdge.xcodeproj -scheme NewsEdge -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: web all pass (2 live-only suites skipped); iOS `** TEST SUCCEEDED **` (the iOS copy of the config now has an `indirect` block it ignores). Use any installed simulator if `iPhone 17 Pro` is missing.

- [ ] **Step 7: Commit, push, open the PR**

```bash
cd /Users/nrebello/Documents/NewsEdge
git add frontend/src/lib/local/indirect.shadow.test.js data/news_config.json frontend/src/data/newsConfig.json ios/NewsEdge/NewsEdge/Resources/NewsConfig.json README.md docs/superpowers/plans/2026-11-20-semantic-indirect-relevance-web.md
git commit -m "Phase 4: semantic indirect relevance on web (shadow mode), evaluation harness"
git push -u origin semantic/p4-web-indirect-relevance
gh pr create --base epic/semantic-news-pipeline --title "Phase 4: semantic indirect relevance on web (shadow mode)" --body "<what changed, the sweep numbers, how to reproduce, mode stays shadow; iOS is Phase 4b>"
```
Expected: PR URL printed. The PR body has no Claude attribution footer (user preference).
