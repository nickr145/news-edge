from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx
try:
    import pandas as pd
except Exception:  # pragma: no cover - environment-dependent fallback
    pd = None

from app.core.config import get_settings


@dataclass
class PriceFeatures:
    rsi_14: float
    momentum_5d: float
    bb_position: float
    volume_ratio: float


@dataclass
class RiskMetrics:
    annualized_volatility: float
    beta_to_benchmark: float
    max_drawdown: float
    high_water_mark: float
    cumulative_return: float


def _compute_rsi(close: pd.Series, period: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(period).mean()
    loss = (-delta.clip(upper=0)).rolling(period).mean()
    rs = gain / loss.replace(0, 1e-9)
    return 100 - (100 / (1 + rs))


def _compute_bb_position(close: pd.Series, window: int = 20) -> pd.Series:
    ma = close.rolling(window).mean()
    std = close.rolling(window).std()
    lower = ma - (2 * std)
    upper = ma + (2 * std)
    return ((close - lower) / (upper - lower).replace(0, 1e-9)).clip(0, 1)


def fetch_bars_dataframe(ticker: str, days: int = 365) -> pd.DataFrame:
    if pd is None:
        return None
    settings = get_settings()
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)

    if not settings.alpaca_api_key or not settings.alpaca_secret_key:
        return pd.DataFrame()

    url = f"{settings.alpaca_rest_url}/stocks/{ticker.upper()}/bars"
    params = {
        "timeframe": "1Day",
        "start": start.isoformat(),
        "end": end.isoformat(),
        "limit": days,
        "feed": settings.alpaca_data_feed,
    }
    headers = {
        "APCA-API-KEY-ID": settings.alpaca_api_key,
        "APCA-API-SECRET-KEY": settings.alpaca_secret_key,
    }

    with httpx.Client(timeout=15) as client:
        try:
            response = client.get(url, params=params, headers=headers)
            response.raise_for_status()
            payload = response.json()
        except Exception:
            return pd.DataFrame()

    bars = payload.get("bars", [])
    if not bars:
        return pd.DataFrame()

    df = pd.DataFrame(bars)
    df.rename(
        columns={"t": "timestamp", "o": "open", "h": "high", "l": "low", "c": "close", "v": "volume"},
        inplace=True,
    )
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
    df.sort_values("timestamp", inplace=True)
    return df


def compute_price_features(ticker: str) -> PriceFeatures:
    if pd is None:
        return PriceFeatures(rsi_14=50.0, momentum_5d=0.0, bb_position=0.5, volume_ratio=1.0)

    df = fetch_bars_dataframe(ticker)
    if df is None or df.empty or len(df) < 30:
        return PriceFeatures(rsi_14=50.0, momentum_5d=0.0, bb_position=0.5, volume_ratio=1.0)

    close = df["close"].astype(float)
    volume = df["volume"].astype(float)

    rsi = _compute_rsi(close)
    momentum = close.pct_change(5)
    bb = _compute_bb_position(close)
    vol_ratio = volume / volume.rolling(20).mean().replace(0, 1e-9)

    return PriceFeatures(
        rsi_14=float(rsi.iloc[-1]) if pd.notna(rsi.iloc[-1]) else 50.0,
        momentum_5d=float(momentum.iloc[-1]) if pd.notna(momentum.iloc[-1]) else 0.0,
        bb_position=float(bb.iloc[-1]) if pd.notna(bb.iloc[-1]) else 0.5,
        volume_ratio=float(vol_ratio.iloc[-1]) if pd.notna(vol_ratio.iloc[-1]) else 1.0,
    )


def compute_risk_metrics(ticker: str, benchmark: str = "SPY", days: int = 365) -> RiskMetrics:
    if pd is None:
        return RiskMetrics(annualized_volatility=0.0, beta_to_benchmark=0.0, max_drawdown=0.0, high_water_mark=0.0, cumulative_return=0.0)

    df = fetch_bars_dataframe(ticker, days=days)
    bench = fetch_bars_dataframe(benchmark, days=days)
    if df is None or bench is None or df.empty or bench.empty or len(df) < 30 or len(bench) < 30:
        return RiskMetrics(annualized_volatility=0.0, beta_to_benchmark=0.0, max_drawdown=0.0, high_water_mark=0.0, cumulative_return=0.0)

    prices = df[["timestamp", "close"]].copy()
    prices["ret"] = prices["close"].astype(float).pct_change()

    bench_prices = bench[["timestamp", "close"]].copy()
    bench_prices["bench_ret"] = bench_prices["close"].astype(float).pct_change()

    merged = prices.merge(bench_prices[["timestamp", "bench_ret"]], on="timestamp", how="inner").dropna()
    if merged.empty:
        return RiskMetrics(annualized_volatility=0.0, beta_to_benchmark=0.0, max_drawdown=0.0, high_water_mark=0.0, cumulative_return=0.0)

    returns = merged["ret"].astype(float)
    bench_returns = merged["bench_ret"].astype(float)

    annualized_vol = float(returns.std() * (252**0.5))
    cov = float(returns.cov(bench_returns))
    var_bench = float(bench_returns.var())
    beta = cov / var_bench if var_bench > 0 else 0.0

    close = prices["close"].astype(float)
    running_max = close.cummax()
    drawdown = (close / running_max) - 1.0
    max_dd = float(drawdown.min()) if len(drawdown) else 0.0
    hwm = float(running_max.iloc[-1]) if len(running_max) else 0.0
    cumulative = float((close.iloc[-1] / close.iloc[0]) - 1.0) if len(close) > 1 and close.iloc[0] != 0 else 0.0

    return RiskMetrics(
        annualized_volatility=annualized_vol,
        beta_to_benchmark=float(beta),
        max_drawdown=max_dd,
        high_water_mark=hwm,
        cumulative_return=cumulative,
    )
