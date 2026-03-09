from datetime import datetime

from pydantic import BaseModel, ConfigDict


class PredictionRequest(BaseModel):
    horizon_days: int = 5


class PredictionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ticker: str
    predicted_at: datetime
    recommendation: str
    confidence: float
    sentiment_score: float
    price_rsi: float
    feature_importances: dict
    horizon_days: int
