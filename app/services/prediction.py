from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.ml.model import FEATURE_COLUMNS, explain_row, load_bundle, predict_proba_row, train_model
from app.models.prediction import Prediction
from app.models.sentiment import SentimentScore
from app.services.analytics import get_sentiment_summary
from app.services.price_data import compute_price_features
from app.utils.stats import std


@dataclass
class InferenceFeatureRow:
    ewma_sentiment_1d: float
    ewma_sentiment_7d: float
    sentiment_volatility: float
    article_volume_24h: float
    rsi_14: float
    momentum_5d: float
    bb_position: float
    volume_ratio: float

    def to_dict(self) -> dict[str, float]:
        return {col: float(getattr(self, col)) for col in FEATURE_COLUMNS}


def _sentiment_volatility_7d(db: Session, ticker: str) -> float:
    since = datetime.now(timezone.utc) - timedelta(days=7)
    rows = db.execute(
        select(SentimentScore.compound)
        .where(SentimentScore.ticker == ticker.upper())
        .where(SentimentScore.scored_at >= since)
        .order_by(SentimentScore.scored_at.asc())
    ).all()
    values = [float(row[0]) for row in rows]
    return std(values)


def _article_volume_24h(db: Session, ticker: str) -> int:
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    rows = db.execute(
        select(SentimentScore.id)
        .where(SentimentScore.ticker == ticker.upper())
        .where(SentimentScore.scored_at >= since)
    ).all()
    return len(rows)


def _build_inference_row(db: Session, ticker: str) -> InferenceFeatureRow:
    summary_1d = get_sentiment_summary(db, ticker=ticker, days=1)
    summary_7d = get_sentiment_summary(db, ticker=ticker, days=7)
    price = compute_price_features(ticker)

    return InferenceFeatureRow(
        ewma_sentiment_1d=summary_1d.ewma_compound,
        ewma_sentiment_7d=summary_7d.ewma_compound,
        sentiment_volatility=_sentiment_volatility_7d(db, ticker),
        article_volume_24h=float(_article_volume_24h(db, ticker)),
        rsi_14=price.rsi_14,
        momentum_5d=price.momentum_5d,
        bb_position=price.bb_position,
        volume_ratio=price.volume_ratio,
    )


def train_or_load_model(db: Session, ticker: str):
    settings = get_settings()
    bundle = load_bundle()
    if bundle is not None:
        return bundle

    try:
        from app.ml.dataset import build_training_dataset
    except Exception:
        return None

    dataset = build_training_dataset(db, ticker=ticker, days=365)
    if dataset.empty or len(dataset) < settings.prediction_min_samples:
        return None

    train_df = dataset[[*FEATURE_COLUMNS, "target"]].copy()
    if hasattr(train_df, "replace"):
        train_df = train_df.replace([float("inf"), float("-inf")], None).dropna()
    if len(train_df) == 0:
        return None

    return train_model(train_df)


def run_prediction(db: Session, ticker: str, horizon_days: int | None = None) -> Prediction:
    settings = get_settings()
    horizon = horizon_days or settings.prediction_horizon_days
    ticker = ticker.upper()

    feature_row = _build_inference_row(db, ticker)
    row_dict = feature_row.to_dict()

    bundle = train_or_load_model(db, ticker=ticker)
    if bundle is None:
        recommendation = "HOLD"
        confidence = 0.5
        feature_importances = row_dict
    else:
        proba = predict_proba_row(bundle, row_dict)
        recommendation = max(proba, key=proba.get)
        confidence = float(proba[recommendation])
        feature_importances = explain_row(bundle, row_dict, recommendation)

    prediction = Prediction(
        ticker=ticker,
        recommendation=recommendation,
        confidence=confidence,
        sentiment_score=feature_row.ewma_sentiment_1d,
        price_rsi=feature_row.rsi_14,
        feature_importances=feature_importances,
        horizon_days=horizon,
    )
    db.add(prediction)
    db.commit()
    db.refresh(prediction)
    return prediction
