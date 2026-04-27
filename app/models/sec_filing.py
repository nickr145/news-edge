from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class SecFiling(Base):
    __tablename__ = "sec_filings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ticker: Mapped[str] = mapped_column(String(10), index=True, nullable=False)
    cik: Mapped[str] = mapped_column(String(15), nullable=False)
    accession_number: Mapped[str] = mapped_column(String(25), unique=True, index=True, nullable=False)
    form_type: Mapped[str] = mapped_column(String(10), index=True, nullable=False)
    filed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    filing_url: Mapped[str] = mapped_column(Text, nullable=False)
    # article_id links to the Article created for this filing so it flows through
    # the sentiment pipeline like any other news item.
    article_id: Mapped[int | None] = mapped_column(
        ForeignKey("articles.id", ondelete="SET NULL"), nullable=True
    )
    ingested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
