# NewsEdge

Stock news sentiment for a watchlist you choose: it turns headlines into recency-weighted sentiment, risk metrics and a RISE/STABLE/FALL signal (a direction heuristic, not trading advice). A React web app and a native SwiftUI iOS app (with a widget) both run **without a backend of their own**.

**Live:** https://news-edge-ai.vercel.app

## Architecture

- **Data (public, keyless):** Yahoo Finance (bars, news, symbol search), Nasdaq historical quotes as the price fallback, Google News RSS for first-open history and indirect-relevance searches.
- **Web (`frontend/`):** React + Vite on Vercel. Browsers can't call those sources directly (no CORS), so one allow-listed Vercel Function, `api/proxy.mjs`, forwards five fixed targets with validated parameters. Everything else (sentiment, relevance, grouping, risk, the signal) runs in the browser (`frontend/src/lib/local/`). Articles accrue in `localStorage` for up to 90 days, so history starts at the first visit.
- **iOS (`ios/NewsEdge`):** calls the same sources directly and runs everything on device, with FinBERT (Core ML) for sentiment.
- **Shared data:** `data/news_profiles.json`, `data/news_background.json` and `data/news_config.json` (every tuning threshold for grouping, storylines and embeddings) are the single source of truth; `python3 scripts/sync_news_profiles.py` copies them into the web and iOS apps (`--check` verifies they match). `data/embedding_fixtures.json` holds labelled headline pairs with reference similarities (regenerate with `scripts/build_embedding_fixtures.py`) used to check both embedders and tune thresholds.
- **Embeddings (in progress):** both apps embed each cached article once in the background with all-MiniLM-L6-v2 and store it int8-quantized with the article. Web: quantized ONNX via transformers.js (fetched from huggingface.co and jsdelivr on first use). iOS: Core ML (`scripts/convert_minilm_coreml.py`, 22 MB, downloaded like FinBERT from the `minilm-coreml-v1` release; same vocabulary file as FinBERT). Without the model, grouping stays lexical. Nothing uses the vectors for grouping yet.
- The original FastAPI/Celery/Postgres backend was removed after production moved off Railway. It is in git history up to commit `99fc5b3`.

## Web app

- Autocomplete search by symbol or company name, a watchlist in `localStorage` (7-day EWMA sentiment and article count per ticker), a price and sentiment overlay chart, a sentiment trend and label distribution, a risk panel, a prediction card with a 1/5/14-day horizon, and an event-grouped news feed refreshed every 30 seconds.
- History window (1/7/30/90 days) and minimum relevance (0.20/0.35/0.50/0.70) selectors.
- **Sentiment:** VADER (`vader-sentiment`). FinBERT does not run in the browser here, and VADER is noticeably cruder on headlines than the FinBERT the iOS app uses.
- **Prediction:** no trained model. A rule on recency-weighted sentiment over the horizon (RISE above +0.15, FALL below -0.15, else STABLE); the card lists the input feature values (sentiment, RSI, momentum, Bollinger position, volume ratio).

```bash
cd frontend && npm install
npm run dev      # http://localhost:5173 (the dev server also serves /api/proxy)
npm test         # analytics + data-layer tests (vitest)
npm run build    # output in frontend/dist
```

Deploy: the Vercel project builds with `vercel.json` and needs no environment variables.

## iOS app
- Native SwiftUI app (`ios/NewsEdge`) — runs with **no backend**, Apple Stocks-style: prices and news come straight from keyless Yahoo Finance endpoints (`YahooClient`), news is accrued on device for up to 90 days (`NewsStore`), and FinBERT sentiment, relevance, risk metrics and the prediction rule are computed locally (`Services/Analytics.swift`, a port of the original Python backend's math, with unit tests checked against its output). Dark theme ported 1:1 from the web design tokens.
- Tradeoffs: Yahoo's endpoints are unofficial (daily bars fall back to Nasdaq's historical API, and the last good bars are cached on disk), Yahoo serves only the last day or two of news so the first time a ticker is opened it is backfilled from Google News RSS (sampled across ~4 weeks, so history is sparse and starts at the first open), sentiment is scored on device by FinBERT converted to Core ML (~105 MB, 8-bit weights; generate it with `scripts/convert_finbert_coreml.py` — it is gitignored, and without it the app falls back to Apple's `NLTagger`; the widget always uses `NLTagger`), and there is no trained model (the RISE/STABLE/FALL rule is the same as the web app's).
- Watchlist as card tiles (ticker, EWMA and article count as labeled sub-cells) with swipe-to-remove; tapping a card opens that ticker's detail screen.
- Ticker detail screen: sentiment stats, dual price/sentiment mini-charts, risk metrics, prediction card with feature values, and a relevance-filtered news feed that refreshes every 30 seconds.
- Home-screen widget (`NewsEdgeWidget`) showing 7-day EWMA sentiment for watchlisted tickers, refreshing independently of the app (computed from Yahoo news directly).

## Recency-weighted sentiment (iOS app and web)

The original backend's "EWMA" decayed by 0.3 per *article*, so it only ever reflects the latest dozen headlines: changing the window barely moved it, and its prediction rule used the 1-day value whatever the horizon. The iOS app and the web app use a recency-weighted mean where an article's weight halves every `window / 3` days:

- The **EWMA stat** uses the selected window (1/7/30/90 days), so the window now changes it.
- The **recommendation** uses sentiment over the selected horizon (1/5/14 days, half-life `horizon / 3`) with the same RISE > +0.15 / FALL < -0.15 thresholds, so the horizon buttons can give different answers. Averaging many headlines pulls values toward zero, so STABLE is the common outcome; the thresholds may deserve recalibrating.

## News quality: events and indirect relevance (iOS app and web)

Two problems with counting headlines one by one, and what the clients do about them:

**Same event, many outlets.** Headlines are grouped into *events*: two articles are the same event if, after removing filler words, the publisher suffix and the company's own names, they share most of their words (Jaccard >= 0.5, or >= 75% overlap on 3+ words) within 48 hours. An event is one vote: its value is the weighted mean of its articles, and its weight is `1 + 0.5 * ln(outlets)` (capped at 2.5), so a story carried by ten outlets counts about twice, not ten times. The feed shows one row per event with a "+N outlets" badge, and the "Stories" stat counts events.

**News that doesn't name the company.** Each ticker has a profile (`data/news_profiles.json`): sector templates plus curated overrides for ~57 large caps listing people, suppliers/customers and competitors, and per-sector macro/policy terms. A headline is classified into a *channel*, which sets its relevance, weight and sign:

| Channel | Relevance | Sign | Example for NVDA |
|---|---|---|---|
| direct | scored as before (0.35-0.85+); weight = relevance / 0.8, max 1 | + | "Nvidia posts record revenue" |
| people | 0.80 | + | "Jensen Huang has been ousted" |
| supply chain | 0.50 | + | "TSMC warns of capacity shortage" |
| sector | 0.40 | + | "Chip stocks tumble as rates jump" |
| competitor | 0.30 | - | "AMD wins huge cloud contract" |
| macro / policy | 0.25 | + (some sectors -) | "US widens export controls on China" |

The existing relevance selector decides which channels count (0.35 keeps direct, leadership, supply chain and sector; 0.5 drops sector; 0.2 adds competitor and macro). Indirect news is found by four extra Google News searches per ticker (once per session) and kept only if the profile recognises how it bears on the ticker.

**One story, many angles.** Different pieces about one developing story (a CEO exit: the resignation, the fallout, "what happens now") are different events, but together they would dominate the sentiment. A term is treated as a *storyline* when it bursts: it is in at least 4 events within +/-72h of an event and at least 12% of them, and at least 3x as common there as in the rest of the 30-day set (when the story fills the whole sample, so there is no "rest" to compare with, it needs 6 events and 15% instead). The k-th event of a storyline within that window counts for `1/sqrt(k)` of its weight, floored at 0.25: first reports count in full, the pile-on progressively less. The feed marks them "ongoing . counts N%". Words that can never be a storyline: ordinary headline vocabulary across tickers (`data/news_background.json`, rebuilt from live news by `scripts/build_background_tokens.mjs`), the ticker's own topical vocabulary (aliases, suppliers, sector/macro terms, competitors), and chronic newsmakers (`chronic` in the profiles: Musk at Tesla). People are otherwise *not* excluded, so a leadership story is detectable. Damping uses 30 days of context even for a 1-day window.

**Known limits**
- *Storyline detection is a heuristic.* It works on shared words, so unrelated stories sharing a surname can be damped together (an "Alice Huang" smuggling probe sits in the Jensen Huang storyline), a word that bursts twice in a month is under-damped (the second burst counts as the first one's baseline), and templated headlines ("... Shares Down 1.9% - Here's Why") can form a storyline of their own.
- *Sentiment is about the text, not the impact.* "Sign" only flips or keeps the headline's polarity. Price-direction news ("oil prices surge") is not captured, and the profiles are a curated starter set (names go stale; sector terms are deliberately conservative). Review before relying on them.
- *Lexical grouping misses paraphrases and storylines.* The same event described in different words, or twenty different pieces about one story (a CEO exit, say), stay separate events. Sentence embeddings, or damping repeated entities within a story, would address that.
- Edit `data/news_profiles.json`, then run `python3 scripts/sync_news_profiles.py` (`--check` verifies the three copies match).

## Tests

```bash
cd frontend && npm test                     # web
xcodebuild test -project ios/NewsEdge/NewsEdge.xcodeproj -scheme NewsEdge \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # iOS (any installed simulator works)
```

The math tests use values produced by the original Python backend on the same synthetic inputs.
