from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.price_label import PriceLabel
from app.models.sentiment import SentimentScore
from app.services.price_data import fetch_bars_dataframe
from app.utils.stats import ewma as compute_ewma, mean, std


def build_training_dataset(db: Session, ticker: str, days: int = 365) -> pd.DataFrame:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = db.execute(
        select(SentimentScore.scored_at, SentimentScore.compound)
        .where(SentimentScore.ticker == ticker)
        .where(SentimentScore.scored_at >= since)
        .order_by(SentimentScore.scored_at.asc())
    ).all()
    if len(rows) < 40:
        return pd.DataFrame()

    sentiment_df = pd.DataFrame(rows, columns=["scored_at", "compound"])
    sentiment_df["day"] = pd.to_datetime(sentiment_df["scored_at"], utc=True).dt.floor("D")

    day_groups = sentiment_df.groupby("day")["compound"].apply(list).reset_index(name="scores")
    day_groups["ewma_sentiment_1d"] = day_groups["scores"].apply(
        lambda x: compute_ewma(x) if x else 0.0
    )
    day_groups["daily_mean"] = day_groups["scores"].apply(lambda x: sum(x) / len(x) if x else 0.0)
    day_groups = day_groups.sort_values("day").reset_index(drop=True)
    day_groups["ewma_sentiment_7d"] = day_groups["daily_mean"].ewm(span=7, min_periods=1).mean()
    day_groups["sentiment_volatility"] = day_groups["scores"].apply(std)
    day_groups["article_volume_24h"] = day_groups["scores"].apply(len)

    bars = fetch_bars_dataframe(ticker, days=days)
    if bars is None or bars.empty or len(bars) < 40:
        return pd.DataFrame()

    bars = bars.copy()
    bars["day"] = bars["timestamp"].dt.floor("D")
    bars["momentum_5d"] = bars["close"].pct_change(5)

    rolling_mean = bars["close"].rolling(20).mean()
    rolling_std = bars["close"].rolling(20).std()
    lower = rolling_mean - 2 * rolling_std
    upper = rolling_mean + 2 * rolling_std
    bars["bb_position"] = ((bars["close"] - lower) / (upper - lower).replace(0, 1e-9)).clip(0, 1)

    delta = bars["close"].diff()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta.clip(upper=0)).rolling(14).mean()
    rs = gain / loss.replace(0, 1e-9)
    bars["rsi_14"] = 100 - 100 / (1 + rs)
    bars["volume_ratio"] = bars["volume"] / bars["volume"].rolling(20).mean().replace(0, 1e-9)

    # Prefer stored price labels (pre-computed, stable) over inline computation.
    stored_labels = _load_stored_labels(db, ticker, since)

    if stored_labels is not None and len(stored_labels) >= 30:
        tech_cols = bars[["day", "rsi_14", "momentum_5d", "bb_position", "volume_ratio"]].copy()
        merged = day_groups.merge(tech_cols, on="day", how="inner")
        merged = merged.merge(stored_labels, on="day", how="inner")
    else:
        bars["forward_return"] = (bars["close"].shift(-5) - bars["close"]) / bars["close"]

        def _label(fr: float) -> str:
            if pd.isna(fr):
                return "STABLE"
            if fr > 0.02:
                return "RISE"
            if fr < -0.02:
                return "FALL"
            return "STABLE"

        bars["target"] = bars["forward_return"].apply(_label)
        merged = day_groups.merge(
            bars[["day", "rsi_14", "momentum_5d", "bb_position", "volume_ratio", "target"]],
            on="day",
            how="inner",
        )

    merged.dropna(inplace=True)
    if merged.empty:
        return merged

    merged.sort_values("day", inplace=True)
    return merged


def _load_stored_labels(db: Session, ticker: str, since: datetime) -> pd.DataFrame | None:
    """Return a DataFrame with columns [day, target] from the price_labels table."""
    rows = db.execute(
        select(PriceLabel.date, PriceLabel.label)
        .where(PriceLabel.ticker == ticker)
        .where(PriceLabel.date >= since.date())
        .where(PriceLabel.forward_return_5d.is_not(None))
    ).all()
    if not rows:
        return None
    df = pd.DataFrame(rows, columns=["day", "target"])
    df["day"] = pd.to_datetime(df["day"], utc=True)
    return df
