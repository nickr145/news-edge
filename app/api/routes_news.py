from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.schemas.news import ArticleOut, SentimentSummaryOut, SentimentTrendOut
from app.services.backfill import backfill_news_for_ticker
from app.services.sentiment import get_sentiment_engine
from app.services.analytics import get_articles_for_ticker, get_sentiment_summary, get_sentiment_trend
from app.services.runtime import news_ingestion

router = APIRouter(prefix="/api/news", tags=["news"])


@router.get("/{ticker}", response_model=list[ArticleOut])
def list_news(
    ticker: str,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    days: int | None = Query(None, ge=1, le=365),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    db: Session = Depends(get_db),
):
    return get_articles_for_ticker(
        db,
        ticker=ticker,
        limit=limit,
        offset=offset,
        days=days,
        min_relevance=min_relevance,
    )


@router.get("/{ticker}/sentiment", response_model=SentimentSummaryOut)
def ticker_sentiment(
    ticker: str,
    days: int = Query(7, ge=1, le=90),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    db: Session = Depends(get_db),
):
    return get_sentiment_summary(db, ticker=ticker, days=days, min_relevance=min_relevance)


@router.get("/{ticker}/trend", response_model=SentimentTrendOut)
def ticker_trend(
    ticker: str,
    hours: int = Query(72, ge=1, le=24 * 30),
    min_relevance: float = Query(0.35, ge=0.0, le=1.0),
    db: Session = Depends(get_db),
):
    return get_sentiment_trend(db, ticker=ticker, hours=hours, min_relevance=min_relevance)


@router.post("/subscribe/{ticker}")
async def subscribe_ticker(
    ticker: str,
    backfill_days: int = Query(30, ge=1, le=365),
    backfill_limit: int = Query(200, ge=1, le=500),
    db: Session = Depends(get_db),
):
    tickers = await news_ingestion.subscribe_ticker(ticker)
    inserted = 0
    backfill_error = None
    try:
        inserted = backfill_news_for_ticker(db, ticker=ticker, days=backfill_days, limit=backfill_limit)
    except Exception as exc:
        backfill_error = str(exc)
    return {
        "ok": True,
        "ticker": ticker.upper(),
        "subscribed_tickers": tickers,
        "backfill_days": backfill_days,
        "backfilled_articles": inserted,
        "backfill_error": backfill_error,
    }


@router.get("/subscriptions")
async def list_subscriptions():
    return {"subscribed_tickers": await news_ingestion.get_subscribed_tickers()}


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
