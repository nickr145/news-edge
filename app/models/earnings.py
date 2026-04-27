from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class EarningsEvent(Base):
    __tablename__ = "earnings_events"
    __table_args__ = (UniqueConstraint("ticker", "report_date", name="uq_earnings_ticker_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ticker: Mapped[str] = mapped_column(String(10), index=True, nullable=False)
    report_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True, nullable=False)
    fiscal_date_ending: Mapped[str | None] = mapped_column(String(20), nullable=True)
    estimated_eps: Mapped[float | None] = mapped_column(Numeric(12, 4), nullable=True)
    actual_eps: Mapped[float | None] = mapped_column(Numeric(12, 4), nullable=True)
    surprise_pct: Mapped[float | None] = mapped_column(Numeric(10, 4), nullable=True)
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
