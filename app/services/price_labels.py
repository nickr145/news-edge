from __future__ import annotations

from datetime import datetime, timezone

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.price_label import PriceLabel
from app.services.price_data import fetch_bars_dataframe


_RISE_THRESHOLD = 0.02
_FALL_THRESHOLD = -0.02
_HORIZON_DAYS = 5


def _apply_label(forward_return: float | None) -> str:
    if forward_return is None or pd.isna(forward_return):
        return "STABLE"
    if forward_return > _RISE_THRESHOLD:
        return "RISE"
    if forward_return < _FALL_THRESHOLD:
        return "FALL"
    return "STABLE"


def backfill_price_labels(db: Session, ticker: str, days: int = 400) -> int:
    """Fetch Alpaca daily bars, compute 5-day forward returns, upsert to price_labels.

    Rows within the last HORIZON_DAYS are always updated since their forward
    return is still incomplete (not all 5 future bars have arrived yet).
    """
    ticker = ticker.upper()
    df = fetch_bars_dataframe(ticker, days=days)
    if df is None or df.empty or len(df) < _HORIZON_DAYS + 1:
        return 0

    df = df.copy()
    df["date"] = df["timestamp"].dt.date
    df["forward_return_5d"] = (df["close"].shift(-_HORIZON_DAYS) - df["close"]) / df["close"]
    df["label"] = df["forward_return_5d"].apply(_apply_label)

    now = datetime.now(timezone.utc)

    existing: dict[object, PriceLabel] = {
        row.date: row
        for row in db.execute(
            select(PriceLabel).where(PriceLabel.ticker == ticker)
        ).scalars().all()
    }

    inserted = 0
    for _, bar in df.iterrows():
        date = bar["date"]
        fr = float(bar["forward_return_5d"]) if pd.notna(bar["forward_return_5d"]) else None
        label = bar["label"]
        close = float(bar["close"])

        if date in existing:
            rec = existing[date]
            rec.forward_return_5d = fr
            rec.label = label
            rec.fetched_at = now
        else:
            db.add(PriceLabel(
                ticker=ticker,
                date=date,
                close_price=close,
                forward_return_5d=fr,
                label=label,
                fetched_at=now,
            ))
            inserted += 1

    db.commit()
    return inserted
