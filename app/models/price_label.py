from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Date, DateTime, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PriceLabel(Base):
    __tablename__ = "price_labels"
    __table_args__ = (UniqueConstraint("ticker", "date", name="uq_price_label_ticker_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    ticker: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    date: Mapped[datetime] = mapped_column(Date, nullable=False, index=True)
    close_price: Mapped[float | None] = mapped_column(Numeric(12, 4), nullable=True)
    forward_return_5d: Mapped[float | None] = mapped_column(Numeric(10, 6), nullable=True)
    label: Mapped[str] = mapped_column(String(10), nullable=False, default="STABLE")
    fetched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
