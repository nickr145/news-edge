from __future__ import annotations

from app.db.session import SessionLocal
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
