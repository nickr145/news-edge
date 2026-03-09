# NewsEdge

Real-time stock news sentiment platform with async ingestion, NLP scoring, technical-feature extraction, and XGBoost recommendation inference.

## Implemented

### Backend
- FastAPI API + WebSocket server.
- Redis Stream buffering (`news_stream`) for incoming Alpaca news events.
- Celery worker tasks for async persistence + sentiment scoring.
- PostgreSQL/SQLite storage models:
  - `articles`
  - `article_tickers`
  - `sentiment_scores`
  - `predictions`
- Alpaca REST bar ingestion + technical indicators:
  - RSI(14)
  - 5-day momentum
  - Bollinger Band position
  - volume ratio
- XGBoost training/inference pipeline:
  - dataset builder (`app/ml/dataset.py`)
  - model artifact save/load (`joblib`)
  - prediction probabilities (`BUY/HOLD/SELL`)

### Frontend
- React + Vite dashboard.
- Ticker search route (`/`).
- Ticker dashboard route (`/ticker/:symbol`) with:
  - live news feed
  - sentiment summary/trend charts
  - prediction trigger + recommendation card

### Dev/Infra
- Docker Compose services: `api`, `worker`, `consumer`, `db`, `redis`, `frontend`.
- Alembic setup + initial migration.
- Pytest suite (lightweight unit tests).
- Benchmarks:
  - WebSocket latency script
  - Locust load profile

## Project Structure

- `app/main.py`: FastAPI app lifecycle and routers.
- `app/services/ingestion.py`: Alpaca WebSocket producer -> Redis Stream.
- `app/streams/news_stream.py`: Redis Stream helpers.
- `app/tasks/news_tasks.py`: Celery task for persist+score.
- `app/services/price_data.py`: Alpaca REST bar fetch + indicators.
- `app/ml/`: training dataset + XGBoost model code.
- `app/services/prediction.py`: model load/train + inference row assembly.
- `frontend/`: React app.
- `backend_alembic/`: migrations.
- `tests/`: unit tests.

## API Endpoints

- `GET /health`
- `GET /api/news/{ticker}`
- `GET /api/news/{ticker}/sentiment`
- `GET /api/news/{ticker}/trend`
- `POST /api/news/mock/{ticker}` (dev helper)
- `GET /api/price/{ticker}/bars`
- `GET /api/price/{ticker}/features`
- `POST /api/predict/{ticker}` (async Celery job)
- `GET /api/predict/job/{job_id}`
- `POST /api/predict/{ticker}/sync`
- `GET /api/predict/result/{prediction_id}`
- `GET /api/predict/{ticker}/history`
- `WS /ws/news/{ticker}`

## Local Setup

1. Copy environment:

```bash
cp .env.example .env
```

2. Run full stack:

```bash
docker compose up --build
```

3. Open:
- API docs: `http://localhost:8000/docs`
- Frontend: `http://localhost:5173`

## Celery/Stream Flow

1. Ingestion service receives Alpaca news events.
2. Event is appended to Redis Stream (`XADD`).
3. Consumer process reads stream with consumer group (`XREADGROUP`).
4. Consumer enqueues Celery task per event.
5. Worker persists article/tickers and writes sentiment rows.

## Training + Inference

- Manual training script:

```bash
python -m app.scripts.train_model
```

- Prediction endpoint uses saved model artifact from `MODEL_ARTIFACT_PATH`.
- If no model artifact exists and minimum samples are insufficient, fallback output is conservative `HOLD`.

## Testing

```bash
pytest -q
```

## Migrations

Apply migration:

```bash
alembic upgrade head
```

## Benchmarks

WebSocket latency sample:

```bash
python -m app.scripts.benchmark_ws_latency
```

Locust load test:

```bash
locust -f locustfile.py --host http://localhost:8000
```

## Notes

- `SENTIMENT_MODEL=finbert` is supported by interface, but the heavy Transformers/Torch deps are not pre-pinned in `requirements.txt` to keep baseline environment lightweight.
- For production-grade throughput, add GPU-backed FinBERT microservice batching and SHAP-based explanation fields in `predictions.feature_importances`.
