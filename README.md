# NewsEdge

Real-time stock news sentiment platform with historical backfill, live streaming ingestion, ticker relevance filtering, ML-powered predictions, risk analytics, and a React web dashboard backed by a FastAPI service, and a standalone native iOS app that needs no backend.

**Live:** https://news-edge-ai.vercel.app

## Features

### Data + Ingestion
- Alpaca News WebSocket ingestion for real-time events.
- Historical backfill via Alpaca News REST on ticker subscribe.
- Web backfill via web scraping as a secondary source.
- Redis Streams buffer and Celery workers for async persistence and scoring.
- PostgreSQL (or SQLite fallback) for articles, sentiment scores, predictions, and price labels.
- Overfetch-then-filter pattern ensures article counts are consistent across endpoints.

### NLP + Analytics
- FinBERT (financial-domain transformer) as the default sentiment engine, VADER as fallback.
- Configurable via `SENTIMENT_MODEL` env var (`finbert` or `vader`).
- Batch inference (`score_many`) for efficient backfill throughput.
- Rolling sentiment stats: mean, std, EWMA.
- Relevance scoring to suppress weak cross-market articles.
- Daily sentiment trend bucketing using article publish date for accurate historical spread.

### ML + Prediction
- XGBoost model trained on sentiment features + technical indicators (RSI, momentum, Bollinger Band position, volume ratio).
- SHAP explanations returned with every prediction, showing feature contributions to the signal.
- Prediction horizon: 1, 5, or 14 days. The Railway backend stores it but its fallback rule ignores it (it always uses the 1-day EWMA); the iOS app and the backendless web mode use it (see below).
- Prediction falls back to a sentiment-threshold rule (`RISE` above +0.15 EWMA, `FALL` below -0.15, else `STABLE`) when no trained model artifact is available or there's insufficient data to train one.
- 5-day forward return labels (`RISE` / `STABLE` / `FALL` at ±2% threshold) persisted to `price_labels` table via Alpaca bars.
- Celery Beat schedule:
  - Daily at 01:00 UTC: refresh price labels for all tracked tickers.
  - Weekly Monday at 03:00 UTC: retrain XGBoost model on combined dataset across all tickers.

### Risk Metrics
- Annualized volatility.
- Beta vs benchmark (default `SPY`).
- Max drawdown.
- High-water mark.
- Cumulative return.

### Frontend
- React + Vite dashboard.
- Autocomplete search bar — matches by ticker symbol and company name (e.g. typing `"amazon"` or `"bank america"` resolves to the correct ticker). Keyboard navigation supported.
- Watchlist persisted to `localStorage` — add/remove tickers from any ticker page, view a live mini-dashboard on the home page showing 7-day EWMA sentiment and article count per ticker.
- Dual-axis price & sentiment overlay chart — close price and daily sentiment score on a shared time axis, gaps bridged over non-trading days.
- Sentiment trend chart and label distribution chart.
- Prediction card with interactive horizon selector (1 / 5 / 14 days) and SHAP bar chart showing top 5 feature contributions.
- Risk panel with all risk metrics.
- Relevance-filtered live news feed via WebSocket.
- History window selector (`1 / 7 / 30 / 90 days`) and min relevance selector (`0.20 / 0.35 / 0.50 / 0.70`).

### iOS App
- Native SwiftUI app (`ios/NewsEdge`) — runs with **no backend**, Apple Stocks-style: prices and news come straight from keyless Yahoo Finance endpoints (`YahooClient`), news is accrued on device for up to 90 days (`NewsStore`), and FinBERT sentiment, relevance, risk metrics and the prediction rule are computed locally (`Services/Analytics.swift`, a port of the backend math with unit tests checked against the Python output). Dark theme ported 1:1 from the web design tokens.
- Tradeoffs: Yahoo's endpoints are unofficial (daily bars fall back to Nasdaq's historical API, and the last good bars are cached on disk), Yahoo serves only the last day or two of news so the first time a ticker is opened it is backfilled from Google News RSS (sampled across ~4 weeks, so history is sparse and starts at the first open), sentiment is scored on device by FinBERT converted to Core ML (~105 MB, 8-bit weights; generate it with `scripts/convert_finbert_coreml.py` — it is gitignored, and without it the app falls back to Apple's `NLTagger`; the widget always uses `NLTagger`), and there is no trained model (the RISE/STABLE/FALL rule matches the backend's fallback).
- Watchlist as card tiles (ticker, EWMA and article count as labeled sub-cells) with swipe-to-remove; tapping a card opens that ticker's detail screen.
- Ticker detail screen: sentiment stats, dual price/sentiment mini-charts, risk metrics, prediction card with SHAP feature bars, and a relevance-filtered news feed that refreshes every 30 seconds.
- Home-screen widget (`NewsEdgeWidget`) showing 7-day EWMA sentiment for watchlisted tickers, refreshing independently of the app (computed from Yahoo news directly).

## Backendless web mode (prototype)

The web app can run without the FastAPI backend, like the iOS app: build or run it with `VITE_BACKENDLESS=1` and every `api.get/post` call is answered in the browser (`frontend/src/lib/local/`).

```bash
cd frontend && npm install
VITE_BACKENDLESS=1 npm run dev      # http://localhost:5173, no Docker/Railway needed
npm test                            # analytics + data-layer tests (vitest)
```

- **Data:** Yahoo Finance (bars + news), Nasdaq historical quotes as the price fallback, and Google News RSS for a first-open history backfill. Browsers can't call these directly (no CORS headers), so they go through one tiny allow-listed proxy, `api/proxy.mjs`: a Vercel Function in production and a Vite middleware in `npm run dev`. It forwards only five fixed targets and validates every parameter, but it is still a (stateless) serverless function, so "no backend" means no always-on server, database or Redis.
- **Math:** `analytics.js` ports the backend's relevance, dedup, risk metrics, RSI/Bollinger features and the RISE/STABLE/FALL rule; tests use values produced by the Python code. Sentiment aggregation is deliberately *not* a straight port, see "Recency-weighted sentiment" below.
- **Sentiment:** VADER (`vader-sentiment`, the backend's default engine). FinBERT does not run in the browser here, and VADER is noticeably cruder on headlines than the FinBERT the iOS app uses.
- **Storage:** articles accrue in `localStorage` (up to 90 days) and the last good bars are cached, so history starts at the first visit.
- **Without the flag** the app talks to the backend exactly as before, so the Railway backend can only be retired once this mode (or an equivalent) ships.

## Recency-weighted sentiment (iOS app and backendless web)

The backend's "EWMA" decays by 0.3 per *article*, so it only ever reflects the latest dozen headlines: changing the window barely moved it, and its prediction rule used the 1-day value whatever the horizon. The iOS app and backendless web mode instead use a recency-weighted mean where an article's weight halves every `window / 3` days:

- The **EWMA stat** uses the selected window (1/7/30/90 days), so the window now changes it.
- The **recommendation** uses sentiment over the selected horizon (1/5/14 days, half-life `horizon / 3`) with the same RISE > +0.15 / FALL < -0.15 thresholds, so the horizon buttons can give different answers. Averaging many headlines pulls values toward zero, so STABLE is the common outcome; the thresholds may deserve recalibrating.
- The Railway backend is unchanged and keeps the old behavior.

## News quality: events and indirect relevance (iOS app and backendless web)

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
- The Railway backend is unchanged. Edit `data/news_profiles.json`, then run `python3 scripts/sync_news_profiles.py` (`--check` verifies the three copies match).

## Main Endpoints

- `GET /health`
- `GET /api/news/{ticker}?days=&limit=&min_relevance=`
- `GET /api/news/{ticker}/sentiment?days=&min_relevance=`
- `GET /api/news/{ticker}/trend?hours=&min_relevance=`
- `POST /api/news/subscribe/{ticker}?backfill_days=&backfill_limit=`
- `GET /api/news/subscriptions`
- `POST /api/news/mock/{ticker}` (dev helper)
- `GET /api/price/{ticker}/bars?limit=`
- `GET /api/price/{ticker}/features`
- `GET /api/price/{ticker}/risk?benchmark=SPY&days=365`
- `POST /api/predict/{ticker}` (async)
- `GET /api/predict/job/{job_id}`
- `POST /api/predict/{ticker}/sync`
- `GET /api/predict/result/{prediction_id}`
- `GET /api/predict/{ticker}/history`
- `WS /ws/news/{ticker}`

## Local Run

1. Create env:

```bash
cp .env.example .env
```

2. Start stack:

```bash
docker compose up --build
```

3. Open:
- API docs: `http://localhost:8000/docs`
- Frontend: `http://localhost:5173`

4. Run Alembic migrations (first run or after schema changes):

```bash
docker compose exec api alembic upgrade head
```

## Typical Workflow

1. Open ticker page in frontend — search by symbol or company name.
2. App calls subscribe endpoint with backfill window.
3. Historical news is fetched, scored with FinBERT, and persisted.
4. Live WebSocket continues incremental updates.
5. Dashboard updates sentiment trend, price & sentiment overlay, relevance-filtered feed, risk metrics.
6. Run a prediction with the desired horizon to get a `RISE` / `STABLE` / `FALL` price-direction signal (not a trading recommendation) with SHAP explanations.

## Training

Manually trigger a retrain:

```bash
docker compose exec worker celery call newsedge.retrain_models
```

Or run the training script directly:

```bash
python -m app.scripts.train_model
```

The Celery Beat scheduler retrains automatically every Monday at 03:00 UTC and refreshes price labels daily at 01:00 UTC.

## Tests

```bash
pytest -q
```

Tests run against an in-memory SQLite database (via `StaticPool`) so they are fully isolated from the local dev database and always reflect the latest schema.

## Notes

- FinBERT requires `torch`. Without it, the engine silently falls back to VADER. Ensure `torch` is installed in the Docker image (`docker compose up --build` after any `requirements.txt` change).
- Price labels must be populated before the XGBoost model can use stored targets. Run `newsedge.refresh_price_labels` or wait for the daily Beat task on first deploy.
