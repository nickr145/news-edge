"""Earnings calendar ingestion (Finnhub) and near-earnings article tagging.

After fetching, `tag_articles_near_earnings` scans existing articles for the
ticker and writes `near_earnings=True` + `earnings_date` into their
raw_payload. The ML dataset builder can then use this as a binary feature.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session, attributes

from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.earnings import EarningsEvent

_NEAR_DAYS = 3  # articles within ±3 days of an earnings date get tagged


# ── Fetch ─────────────────────────────────────────────────────────────────────

def _fetch_finnhub_earnings(
    ticker: str,
    from_date: datetime,
    to_date: datetime,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.finnhub_api_key:
        return []
    try:
        r = httpx.get(
            "https://finnhub.io/api/v1/calendar/earnings",
            params={
                "from": from_date.strftime("%Y-%m-%d"),
                "to": to_date.strftime("%Y-%m-%d"),
                "symbol": ticker,
                "token": settings.finnhub_api_key,
            },
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
        return data.get("earningsCalendar") or []
    except Exception:
        return []


def _parse_date(date_str: str | None) -> datetime | None:
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        return None


# ── Persist ───────────────────────────────────────────────────────────────────

def backfill_earnings(
    db: Session,
    ticker: str,
    lookback_days: int = 365,
    lookahead_days: int = 90,
) -> int:
    """Fetch and store earnings events. Returns count of new rows inserted."""
    ticker = ticker.upper()
    now = datetime.now(timezone.utc)
    from_date = now - timedelta(days=lookback_days)
    to_date = now + timedelta(days=lookahead_days)

    events = _fetch_finnhub_earnings(ticker, from_date, to_date)
    if not events:
        return 0

    inserted = 0
    for ev in events:
        report_date = _parse_date(ev.get("date"))
        if not report_date:
            continue

        existing = db.scalar(
            select(EarningsEvent).where(
                EarningsEvent.ticker == ticker,
                EarningsEvent.report_date == report_date,
            )
        )

        est = ev.get("epsEstimate")
        act = ev.get("epsActual")
        surprise = None
        if est is not None and act is not None and float(est or 0) != 0:
            surprise = (float(act) - float(est)) / abs(float(est)) * 100

        if existing:
            # Fill in actual EPS once a past estimate becomes a reported result.
            if act is not None and existing.actual_eps is None:
                existing.actual_eps = act
                existing.surprise_pct = surprise
            continue

        db.add(
            EarningsEvent(
                ticker=ticker,
                report_date=report_date,
                fiscal_date_ending=ev.get("fiscalDateEnding"),
                estimated_eps=est,
                actual_eps=act,
                surprise_pct=surprise,
            )
        )
        inserted += 1

    if inserted:
        db.commit()

    return inserted


# ── Tag ───────────────────────────────────────────────────────────────────────

def tag_articles_near_earnings(db: Session, ticker: str) -> int:
    """Mark articles published within ±3 days of any earnings date for ticker.

    Writes `near_earnings: True` and `earnings_date: "YYYY-MM-DD"` into the
    article's raw_payload so downstream ML features can use the flag.
    """
    ticker = ticker.upper()

    earnings_dates: list[datetime] = [
        row[0]
        for row in db.execute(
            select(EarningsEvent.report_date).where(EarningsEvent.ticker == ticker)
        ).all()
    ]
    if not earnings_dates:
        return 0

    # Normalise to UTC-aware datetimes
    aware_dates = [
        ed if ed.tzinfo else ed.replace(tzinfo=timezone.utc) for ed in earnings_dates
    ]

    article_rows = (
        db.execute(
            select(Article)
            .join(ArticleTicker, Article.id == ArticleTicker.article_id)
            .where(ArticleTicker.ticker == ticker)
        )
        .scalars()
        .all()
    )

    tagged = 0
    for article in article_rows:
        if (article.raw_payload or {}).get("near_earnings"):
            continue  # already tagged

        pub = article.published_at
        if pub.tzinfo is None:
            pub = pub.replace(tzinfo=timezone.utc)

        nearest = min(aware_dates, key=lambda ed: abs((pub - ed).days))
        if abs((pub - nearest).days) <= _NEAR_DAYS:
            new_payload = dict(article.raw_payload or {})
            new_payload["near_earnings"] = True
            new_payload["earnings_date"] = nearest.strftime("%Y-%m-%d")
            article.raw_payload = new_payload
            # Explicitly flag the JSON column as modified so SQLAlchemy tracks it.
            attributes.flag_modified(article, "raw_payload")
            tagged += 1

    if tagged:
        db.commit()

    return tagged
