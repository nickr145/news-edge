# Semantic indirect relevance (Phase 4)

Part of the semantic news pipeline epic (`epic/semantic-news-pipeline`). Phase 4 ships web first, then iOS as 4b, each in shadow mode.

## Goal

Recall only. Rescue headlines that bear on a ticker but contain none of the keywords in its profile (for example "Taiwan quake halts chip fabs" for NVDA). Precision work (dropping keyword false positives) is out of scope.

## Today

- `exposureOf(profile, headline, symbols)` in `frontend/src/lib/local/news.js` classifies a headline into a channel (direct, people, supply, sector, competitor, macro) by matching profile terms. Mirrored in `ios/.../Services/NewsEvents.swift`.
- `client.js` runs four extra Google News queries per ticker (`indirectQueries`) and drops every result `exposureOf` rejects, so rejected articles are never cached.
- `eventsFor` requires `exposureOf` to succeed and `relevance >= min_relevance` (default 0.35).

## Design

### 1. Candidate pool
Google results that `exposureOf` rejects are cached with a `cand: true` flag instead of dropped. They are embedded in the background like any article, never shown or counted unless admitted, and age out with the 30-day cache.

### 2. Anchors
Per ticker and channel (people, supply, sector, competitor, macro), a few anchor sentences are generated from the existing profile, for example "Supply chain disruption at TSMC or Samsung affecting Nvidia". They are embedded once with the same MiniLM model and cached, keyed by profile content and model version. The channel relevance, weight and sign table is unchanged.

### 3. Admission
`semanticExposure(profile, article, anchors)` runs only when `exposureOf` returns nothing, so a keyword match always wins and is never overridden. A candidate is admitted when:
- its best cosine to any anchor is at least `indirect.semantic.threshold`, and
- that channel beats the runner-up channel by at least `indirect.semantic.margin`.

The result is an exposure object with the winning channel's normal relevance, weight and sign, plus `semantic: true`. The caller's `min_relevance` selector applies as it does for keyword matches.

### 4. Config and rollout
New block in `data/news_config.json` (synced by `scripts/sync_news_profiles.py`):

```json
"indirect": { "semantic": { "mode": "shadow", "threshold": null, "margin": null } }
```

`threshold` and `margin` are set from the shadow evaluation, not guessed. Modes: `off`, `shadow` (compute and log, change nothing) or `on`. Default `shadow`. The decision log records every admission and near miss with cosine, margin and channel, exposed through `newsedge.api.debug.decisions(ticker)` (web) and the matching iOS accessor.

### 5. Evaluation
A `SHADOW=1` vitest harness, like the events and storylines ones, runs live news for the 12 tracked tickers and reports how many candidates would be admitted, by channel, with samples to hand-label for false positives.

## Known ceiling

This only classifies what the four existing Google queries return. If shadow mode shows few genuine misses in that pool, the follow-up is broader queries built from the anchor text. That decision comes from the shadow numbers and is not part of this phase.

## Testing

Web unit tests with synthetic vectors: threshold, margin, keyword-wins, shadow-changes-nothing, candidates-not-counted-unless-admitted. Live harness for threshold tuning. Phase 4b ports the same module and tests to Swift.

## Out of scope

Precision filtering, changes to the channel relevance table, new data sources, and ticker-impact scoring (Phase 5).
