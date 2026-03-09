from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class SentimentScore(Base):
    __tablename__ = "sentiment_scores"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    article_id: Mapped[int] = mapped_column(ForeignKey("articles.id", ondelete="CASCADE"), nullable=False, index=True)
    ticker: Mapped[str] = mapped_column(String(10), index=True)
    model: Mapped[str] = mapped_column(String(20), nullable=False)
    score_positive: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)
    score_negative: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)
    score_neutral: Mapped[float] = mapped_column(Numeric(5, 4), nullable=False)
    compound: Mapped[float] = mapped_column(Numeric(6, 4), nullable=False)
    label: Mapped[str] = mapped_column(String(10), nullable=False)
    scored_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    article: Mapped["Article"] = relationship("Article", back_populates="sentiments")
