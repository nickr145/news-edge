from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.sentiment import SentimentScore
from app.services.price_data import fetch_bars_dataframe
from app.utils.stats import mean, std


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
    day_groups["ewma_sentiment_1d"] = day_groups["scores"].apply(lambda x: x[-1] if x else 0.0)
    day_groups["ewma_sentiment_7d"] = day_groups["scores"].apply(lambda x: sum(x) / len(x) if x else 0.0)
    day_groups["sentiment_volatility"] = day_groups["scores"].apply(std)
    day_groups["article_volume_24h"] = day_groups["scores"].apply(len)

    bars = fetch_bars_dataframe(ticker, days=days)
    if bars.empty or len(bars) < 40:
        return pd.DataFrame()

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

    bars["forward_return"] = (bars["close"].shift(-5) - bars["close"]) / bars["close"]

    def label(fr: float) -> str:
        if pd.isna(fr):
            return "HOLD"
        if fr > 0.02:
            return "BUY"
        if fr < -0.02:
            return "SELL"
        return "HOLD"

    bars["target"] = bars["forward_return"].apply(label)

    merged = day_groups.merge(
        bars[["day", "rsi_14", "momentum_5d", "bb_position", "volume_ratio", "target"]],
        on="day",
        how="inner",
    )

    merged.dropna(inplace=True)
    if merged.empty:
        return merged

    # Ensure lookahead-safe ordering.
    merged.sort_values("day", inplace=True)
    return merged
