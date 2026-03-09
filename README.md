# NewsEdge

Real-time stock news sentiment platform with historical backfill, live streaming ingestion, ticker relevance filtering, risk analytics, and recommendation inference.

## Features

### Data + Ingestion
- Alpaca News WebSocket ingestion for real-time events.
- Historical backfill via Alpaca News REST on ticker subscribe.
- Redis Streams buffer and Celery workers for async persistence/scoring.
- PostgreSQL (or SQLite fallback) for articles, sentiment scores, and predictions.

### NLP + Analytics
- Pluggable sentiment engine (`vader` default, `finbert` interface support).
- Rolling sentiment stats: mean, std, EWMA.
- Relevance scoring to suppress weak cross-market articles.
- Sentiment trend bucketing for charting.

### Prediction + Risk
- Recommendation endpoint (`BUY` / `HOLD` / `SELL`) with confidence.
- XGBoost pipeline scaffold for train/load/infer.
- Risk metrics endpoint with:
  - annualized volatility
  - beta vs benchmark (default `SPY`)
  - max drawdown
  - high-water mark
  - cumulative return

### Frontend
- React + Vite dashboard.
- Ticker search and live feed.
- History window selector (`1/7/30/90 days`).
- Min relevance selector (`0.20/0.35/0.50/0.70`).
- Sentiment charts + prediction card + risk panel.

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

## Typical Workflow

1. Open ticker page in frontend.
2. App calls subscribe endpoint with backfill window.
3. Historical news is fetched + scored.
4. Live WebSocket continues incremental updates.
5. Dashboard updates sentiment, relevance-filtered feed, risk metrics, and prediction.

## Training + Test

Train model artifact:

```bash
python -m app.scripts.train_model
```

Run tests:

```bash
pytest -q
```

## Notes

- If no model artifact is available or samples are insufficient, prediction falls back to conservative `HOLD` behavior.
- FinBERT support exists by interface; production use should pin/serve model dependencies separately for reliability and throughput.
