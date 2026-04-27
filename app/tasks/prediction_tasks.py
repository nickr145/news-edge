from __future__ import annotations

from sqlalchemy import select, distinct

from app.db.session import SessionLocal
from app.ml.model import FEATURE_COLUMNS, load_bundle, save_bundle, train_model
from app.models.sentiment import SentimentScore
from app.services.prediction import run_prediction
from app.tasks.celery_app import celery_app


@celery_app.task(name="newsedge.run_prediction")
def run_prediction_task(ticker: str, horizon_days: int = 5) -> dict:
    with SessionLocal() as db:
        row = run_prediction(db, ticker=ticker, horizon_days=horizon_days)
        return {
            "id": row.id,
            "ticker": row.ticker,
            "recommendation": row.recommendation,
            "confidence": float(row.confidence),
        }


@celery_app.task(name="newsedge.retrain_models")
def retrain_models_task() -> dict:
    """Scheduled weekly: rebuild the XGBoost prediction model from fresh data.

    Iterates every ticker that has sentiment scores, builds a combined training
    dataset, and overwrites the shared model artifact if training succeeds.
    """
    from app.ml.dataset import build_training_dataset
    import pandas as pd

    retrained: list[str] = []
    skipped: list[str] = []
    failed: list[dict] = []

    with SessionLocal() as db:
        tickers: list[str] = list(
            db.execute(select(distinct(SentimentScore.ticker))).scalars().all()
        )

        frames: list[pd.DataFrame] = []
        for ticker in tickers:
            try:
                df = build_training_dataset(db, ticker=ticker, days=365)
                if df.empty:
                    skipped.append(ticker)
                    continue
                frames.append(df)
                retrained.append(ticker)
            except Exception as exc:
                failed.append({"ticker": ticker, "error": str(exc)})

    if not frames:
        return {"status": "skipped", "reason": "no_data", "tickers": tickers}

    combined = pd.concat(frames, ignore_index=True)
    train_df = combined[[*FEATURE_COLUMNS, "target"]].copy()
    train_df = train_df.replace([float("inf"), float("-inf")], None).dropna()

    if len(train_df) == 0:
        return {"status": "skipped", "reason": "empty_after_cleaning"}

    bundle = train_model(train_df)
    if bundle is None:
        return {"status": "failed", "reason": "train_model_returned_none"}

    return {
        "status": "ok",
        "tickers_used": retrained,
        "tickers_skipped": skipped,
        "tickers_failed": failed,
        "rows_trained": int(len(train_df)),
        "metrics": bundle.metadata.get("metrics", {}),
    }


@celery_app.task(name="newsedge.refresh_price_labels")
def refresh_price_labels_task() -> dict:
    """Scheduled daily: fetch Alpaca bars and upsert forward-return labels."""
    from app.services.price_labels import backfill_price_labels

    results: dict[str, int] = {}
    errors: dict[str, str] = {}

    with SessionLocal() as db:
        tickers: list[str] = list(
            db.execute(select(distinct(SentimentScore.ticker))).scalars().all()
        )

    for ticker in tickers:
        with SessionLocal() as db:
            try:
                n = backfill_price_labels(db, ticker=ticker, days=400)
                results[ticker] = n
            except Exception as exc:
                errors[ticker] = str(exc)

    return {"inserted": results, "errors": errors}
