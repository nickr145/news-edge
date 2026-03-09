from fastapi import APIRouter, HTTPException, Query

from app.services.price_data import compute_price_features, compute_risk_metrics, fetch_bars_dataframe

router = APIRouter(prefix="/api/price", tags=["price"])


@router.get("/{ticker}/bars")
def price_bars(ticker: str, limit: int = Query(365, ge=30, le=1000)):
    try:
        df = fetch_bars_dataframe(ticker=ticker, days=limit)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Failed to fetch bars: {exc}")

    if df is None or df.empty:
        return []

    return df.tail(limit).to_dict(orient="records")


@router.get("/{ticker}/features")
def price_features(ticker: str):
    return compute_price_features(ticker).__dict__


@router.get("/{ticker}/risk")
def price_risk(ticker: str, benchmark: str = Query("SPY", min_length=1, max_length=10), days: int = Query(365, ge=60, le=1500)):
    return compute_risk_metrics(ticker=ticker, benchmark=benchmark.upper(), days=days).__dict__
