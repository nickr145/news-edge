import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, BackgroundTasks, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import SessionLocal, get_db
from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.schemas.news import ArticleOut, SentimentSummaryOut, SentimentTrendOut
from app.services.backfill import backfill_news_for_ticker
from app.services.earnings import backfill_earnings, tag_articles_near_earnings
from app.services.news_api import backfill_news_api_articles
from app.services.sec_filings import backfill_sec_filings
from app.services.sentiment import get_sentiment_engine
from app.services.analytics import get_articles_for_ticker, get_sentiment_summary, get_sentiment_trend, get_source_breakdown
from app.services.runtime import news_ingestion
from app.services.web_backfill import backfill_web_news_for_ticker

router = APIRouter(prefix="/api/news", tags=["news"])
settings = get_settings()

# Shared executor so threads are reused across requests, not spawned fresh each time.
_backfill_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="backfill")


async def _run_backfill_concurrent(
    ticker: str,
    company_name: str | None,
    backfill_days: int,
    backfill_limit: int,
    do_web_backfill: bool,
) -> None:
    """Run all backfill sources concurrently; each stage owns its own DB session."""
    loop = asyncio.get_event_loop()

    def _alpaca() -> None:
        with SessionLocal() as db:
            backfill_news_for_ticker(db, ticker=ticker, days=backfill_days, limit=backfill_limit)

    def _news_api() -> None:
        with SessionLocal() as db:
            backfill_news_api_articles(
                db, ticker=ticker, company_name=company_name,
                days=backfill_days, limit=min(backfill_limit, 200),
            )

    def _web() -> None:
        if not (do_web_backfill and settings.enable_web_backfill):
            return
        with SessionLocal() as db:
            backfill_web_news_for_ticker(
                db, ticker=ticker, company_name=company_name,
                days=backfill_days, limit=min(backfill_limit, 300),
            )

    def _earnings() -> None:
        with SessionLocal() as db:
            backfill_earnings(db, ticker=ticker)
            tag_articles_near_earnings(db, ticker=ticker)

    def _sec() -> None:
        with SessionLocal() as db:
            backfill_sec_filings(db, ticker=ticker)

    stages = [_alpaca, _news_api, _web, _earnings, _sec]
    await asyncio.gather(
        *[loop.run_in_executor(_backfill_executor, fn) for fn in stages],
        return_exceptions=True,  # one failing stage never blocks the others
    )


@router.get("/subscriptions")
async def list_subscriptions():
    return {"subscribed_tickers": await news_ingestion.get_subscribed_tickers()}


@router.get("/{ticker}", response_model=list[ArticleOut])
def list_news(
    ticker: str,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    days: int | None = Query(None, ge=1, le=365),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    include_mock: bool = Query(False),
    db: Session = Depends(get_db),
):
    return get_articles_for_ticker(
        db,
        ticker=ticker,
        limit=limit,
        offset=offset,
        days=days,
        min_relevance=min_relevance,
        include_mock=include_mock,
    )


@router.get("/{ticker}/sentiment", response_model=SentimentSummaryOut)
def ticker_sentiment(
    ticker: str,
    days: int = Query(7, ge=1, le=90),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    include_mock: bool = Query(False),
    db: Session = Depends(get_db),
):
    return get_sentiment_summary(
        db,
        ticker=ticker,
        days=days,
        min_relevance=min_relevance,
        include_mock=include_mock,
    )


@router.get("/{ticker}/trend", response_model=SentimentTrendOut)
def ticker_trend(
    ticker: str,
    hours: int = Query(72, ge=1, le=24 * 30),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    include_mock: bool = Query(False),
    db: Session = Depends(get_db),
):
    return get_sentiment_trend(
        db,
        ticker=ticker,
        hours=hours,
        min_relevance=min_relevance,
        include_mock=include_mock,
    )


@router.post("/subscribe/{ticker}")
async def subscribe_ticker(
    ticker: str,
    background_tasks: BackgroundTasks,
    backfill_days: int = Query(30, ge=1, le=365),
    backfill_limit: int = Query(200, ge=1, le=500),
    company_name: str | None = Query(None),
    web_backfill: bool = Query(True),
):
    tickers = await news_ingestion.subscribe_ticker(ticker)
    # Queue all backfill to run concurrently in the background.
    # Returns immediately so the UI is never blocked waiting for external APIs.
    background_tasks.add_task(
        _run_backfill_concurrent,
        ticker=ticker.upper(),
        company_name=company_name,
        backfill_days=backfill_days,
        backfill_limit=backfill_limit,
        do_web_backfill=web_backfill,
    )
    return {
        "ok": True,
        "ticker": ticker.upper(),
        "subscribed_tickers": tickers,
        "backfill_days": backfill_days,
        "status": "backfill_queued",
    }


@router.get("/{ticker}/sources")
def source_breakdown(
    ticker: str,
    days: int = Query(30, ge=1, le=365),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    include_mock: bool = Query(False),
    db: Session = Depends(get_db),
):
    return get_source_breakdown(
        db,
        ticker=ticker,
        days=days,
        min_relevance=min_relevance,
        include_mock=include_mock,
    )


@router.post("/mock/{ticker}")
def create_mock_article(ticker: str, headline: str, summary: str = "", db: Session = Depends(get_db)):
    """Helper endpoint for local testing before connecting live Alpaca feed."""
    ticker = ticker.upper()
    article = Article(
        url=f"https://mock.local/{ticker}/{uuid4().hex}",
        headline=headline,
        summary=summary,
        source="mock",
        published_at=datetime.now(timezone.utc),
        raw_payload={"mock": True},
    )
    db.add(article)
    db.flush()
    db.add(ArticleTicker(article_id=article.id, ticker=ticker))

    sentiment = get_sentiment_engine("vader").score(headline, summary)
    db.add(
        SentimentScore(
            article_id=article.id,
            ticker=ticker,
            model=sentiment.model,
            score_positive=sentiment.score_positive,
            score_negative=sentiment.score_negative,
            score_neutral=sentiment.score_neutral,
            compound=sentiment.compound,
            label=sentiment.label,
        )
    )
    db.commit()
    return {"ok": True, "article_id": article.id}
