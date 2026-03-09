from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, JSON, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Prediction(Base):
    __tablename__ = "predictions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ticker: Mapped[str] = mapped_column(String(10), index=True)
    predicted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    recommendation: Mapped[str] = mapped_column(String(10), nullable=False)
    confidence: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)
    sentiment_score: Mapped[float] = mapped_column(Numeric(6, 4), nullable=False)
    price_rsi: Mapped[float] = mapped_column(Numeric(6, 2), nullable=False)
    feature_importances: Mapped[dict] = mapped_column(JSON, default=dict)
    horizon_days: Mapped[int] = mapped_column(Integer, nullable=False)
