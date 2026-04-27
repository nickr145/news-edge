from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.earnings import EarningsEvent
from app.models.sec_filing import SecFiling
from app.schemas.fundamentals import EarningsEventOut, SecFilingOut
from app.services.earnings import backfill_earnings, tag_articles_near_earnings
from app.services.sec_filings import backfill_sec_filings

router = APIRouter(prefix="/api/fundamentals", tags=["fundamentals"])


@router.get("/{ticker}/earnings", response_model=list[EarningsEventOut])
def get_earnings(
    ticker: str,
    limit: int = Query(40, ge=1, le=100),
    db: Session = Depends(get_db),
):
    rows = (
        db.execute(
            select(EarningsEvent)
            .where(EarningsEvent.ticker == ticker.upper())
            .order_by(EarningsEvent.report_date.desc())
            .limit(limit)
        )
        .scalars()
        .all()
    )
    return rows


@router.post("/{ticker}/earnings/refresh")
def refresh_earnings(ticker: str, db: Session = Depends(get_db)):
    """Fetch the latest earnings calendar from Finnhub and re-tag articles."""
    inserted = backfill_earnings(db, ticker=ticker)
    tagged = tag_articles_near_earnings(db, ticker=ticker)
    return {"ok": True, "ticker": ticker.upper(), "inserted": inserted, "tagged": tagged}


@router.get("/{ticker}/filings", response_model=list[SecFilingOut])
def get_filings(
    ticker: str,
    form_type: str | None = Query(None, description="Filter by form type, e.g. 8-K"),
    limit: int = Query(30, ge=1, le=100),
    db: Session = Depends(get_db),
):
    q = select(SecFiling).where(SecFiling.ticker == ticker.upper())
    if form_type:
        q = q.where(SecFiling.form_type == form_type.upper())
    rows = (
        db.execute(q.order_by(SecFiling.filed_at.desc()).limit(limit)).scalars().all()
    )
    return rows


@router.post("/{ticker}/filings/refresh")
def refresh_filings(ticker: str, db: Session = Depends(get_db)):
    """Pull fresh 8-K / 10-K / 10-Q filings from SEC EDGAR."""
    inserted = backfill_sec_filings(db, ticker=ticker)
    return {"ok": True, "ticker": ticker.upper(), "inserted": inserted}
