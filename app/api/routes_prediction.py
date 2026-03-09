from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.prediction import Prediction
from app.schemas.prediction import PredictionOut, PredictionRequest
from app.services.prediction import run_prediction

router = APIRouter(prefix="/api/predict", tags=["prediction"])


@router.post("/{ticker}")
def predict_ticker_async(ticker: str, payload: PredictionRequest):
    try:
        from app.tasks.prediction_tasks import run_prediction_task
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Async workers unavailable: {exc}")

    task = run_prediction_task.delay(ticker=ticker.upper(), horizon_days=payload.horizon_days)
    return {"job_id": task.id, "status": "queued"}


@router.get("/job/{job_id}")
def get_prediction_job(job_id: str):
    try:
        from celery.result import AsyncResult
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Async workers unavailable: {exc}")

    task = AsyncResult(job_id)
    if task.state in {"PENDING", "RETRY", "STARTED"}:
        return {"job_id": job_id, "status": task.state}
    if task.state == "FAILURE":
        raise HTTPException(status_code=500, detail=str(task.result))
    return {"job_id": job_id, "status": "SUCCESS", "result": task.result}


@router.post("/{ticker}/sync", response_model=PredictionOut)
def predict_ticker_sync(ticker: str, payload: PredictionRequest, db: Session = Depends(get_db)):
    row = run_prediction(db, ticker=ticker, horizon_days=payload.horizon_days)
    return PredictionOut.model_validate(row)


@router.get("/result/{prediction_id}", response_model=PredictionOut)
def get_prediction(prediction_id: int, db: Session = Depends(get_db)):
    row = db.scalar(select(Prediction).where(Prediction.id == prediction_id))
    if not row:
        raise HTTPException(status_code=404, detail="Prediction not found")
    return PredictionOut.model_validate(row)


@router.get("/{ticker}/history", response_model=list[PredictionOut])
def prediction_history(ticker: str, db: Session = Depends(get_db)):
    rows = (
        db.execute(
            select(Prediction)
            .where(Prediction.ticker == ticker.upper())
            .order_by(Prediction.predicted_at.desc())
            .limit(100)
        )
        .scalars()
        .all()
    )
    return [PredictionOut.model_validate(r) for r in rows]
