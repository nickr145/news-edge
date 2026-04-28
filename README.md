# NewsEdge

Real-time stock news sentiment platform with historical backfill, live streaming ingestion, ticker relevance filtering, ML-powered predictions, risk analytics, and an interactive React dashboard.

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
- Configurable prediction horizon: 1, 5, or 14 days.
- Prediction falls back to conservative rule-based `HOLD` when model artifact is unavailable or data is insufficient.
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
6. Run a prediction with the desired horizon to get a `BUY` / `HOLD` / `SELL` signal with SHAP explanations.

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
