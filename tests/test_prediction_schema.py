from datetime import datetime, timezone

from app.schemas.prediction import PredictionOut


def test_prediction_schema_roundtrip():
    payload = PredictionOut(
        id=1,
        ticker="NVDA",
        predicted_at=datetime.now(timezone.utc),
        recommendation="HOLD",
        confidence=0.5,
        sentiment_score=0.1,
        price_rsi=52.0,
        feature_importances={"ewma_sentiment_1d": 0.2},
        horizon_days=5,
    )
    assert payload.ticker == "NVDA"
    assert payload.horizon_days == 5
