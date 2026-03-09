from __future__ import annotations

from datetime import datetime, timedelta, timezone

from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.schemas.news import ArticleOut, SentimentSummaryOut, SentimentTrendOut, SentimentTrendPoint
from app.utils.relevance import compute_ticker_relevance
from app.utils.stats import ewma, mean, std


def get_articles_for_ticker(
    db: Session,
    ticker: str,
    limit: int = 50,
    offset: int = 0,
    days: int | None = None,
    min_relevance: float = 0.35,
) -> list[ArticleOut]:
    ticker = ticker.upper()
    since = None
    if days is not None:
        since = datetime.now(timezone.utc) - timedelta(days=days)

    stmt = (
        select(Article, SentimentScore)
        .join(ArticleTicker, ArticleTicker.article_id == Article.id)
        .outerjoin(
            SentimentScore,
            (SentimentScore.article_id == Article.id) & (SentimentScore.ticker == ticker),
        )
        .where(ArticleTicker.ticker == ticker)
        .order_by(Article.published_at.desc())
        .limit(limit)
        .offset(offset)
    )
    if since is not None:
        stmt = stmt.where(Article.published_at >= since)

    rows = db.execute(stmt).all()
    article_ids = [article.id for article, _ in rows]
    symbol_map = _load_symbol_map(db, article_ids)
    out: list[ArticleOut] = []
    for article, sentiment in rows:
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=article.headline or "",
            summary=article.summary or "",
            symbols=symbol_map.get(article.id, []),
        )
        if relevance < min_relevance:
            continue
        out.append(
            ArticleOut(
                id=article.id,
                url=article.url,
                headline=article.headline,
                summary=article.summary,
                source=article.source,
                published_at=article.published_at,
                sentiment_label=sentiment.label if sentiment else None,
                compound=float(sentiment.compound) if sentiment else None,
                relevance_score=float(round(relevance, 4)),
            )
        )
    return out


def get_sentiment_summary(db: Session, ticker: str, days: int = 7, min_relevance: float = 0.35) -> SentimentSummaryOut:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(days=days)
    stmt = (
        select(SentimentScore.article_id, SentimentScore.compound, SentimentScore.label, Article.headline, Article.summary)
        .join(Article, Article.id == SentimentScore.article_id)
        .where(SentimentScore.ticker == ticker)
        .where(SentimentScore.scored_at >= since)
        .order_by(SentimentScore.scored_at.asc())
    )
    rows = db.execute(stmt).all()
    article_ids = [int(r[0]) for r in rows]
    symbol_map = _load_symbol_map(db, article_ids)

    compounds: list[float] = []
    labels: dict[str, int] = {"POSITIVE": 0, "NEUTRAL": 0, "NEGATIVE": 0}
    for article_id, compound, label, headline, summary in rows:
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=headline or "",
            summary=summary or "",
            symbols=symbol_map.get(int(article_id), []),
        )
        if relevance < min_relevance:
            continue
        compounds.append(float(compound))
        labels[label] = labels.get(label, 0) + 1

    return SentimentSummaryOut(
        ticker=ticker,
        count=len(compounds),
        mean_compound=mean(compounds),
        std_compound=std(compounds),
        ewma_compound=ewma(compounds),
        label_distribution=labels,
    )


def get_sentiment_trend(db: Session, ticker: str, hours: int = 72, min_relevance: float = 0.35) -> SentimentTrendOut:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(hours=hours)

    stmt = (
        select(SentimentScore.article_id, SentimentScore.scored_at, SentimentScore.compound, Article.headline, Article.summary)
        .join(Article, Article.id == SentimentScore.article_id)
        .where(SentimentScore.ticker == ticker)
        .where(SentimentScore.scored_at >= since)
        .order_by(SentimentScore.scored_at.asc())
    )
    rows = db.execute(stmt).all()
    article_ids = [int(r[0]) for r in rows]
    symbol_map = _load_symbol_map(db, article_ids)

    buckets: dict[datetime, list[float]] = defaultdict(list)
    for article_id, scored_at, compound, headline, summary in rows:
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=headline or "",
            summary=summary or "",
            symbols=symbol_map.get(int(article_id), []),
        )
        if relevance < min_relevance:
            continue
        dt = scored_at.replace(minute=0, second=0, microsecond=0)
        buckets[dt].append(float(compound))

    points: list[SentimentTrendPoint] = []
    for dt in sorted(buckets):
        scores = buckets[dt]
        points.append(
            SentimentTrendPoint(bucket=dt, mean_compound=mean(scores), article_count=len(scores))
        )

    return SentimentTrendOut(ticker=ticker, points=points)


def _load_symbol_map(db: Session, article_ids: list[int]) -> dict[int, list[str]]:
    if not article_ids:
        return {}
    stmt = select(ArticleTicker.article_id, ArticleTicker.ticker).where(ArticleTicker.article_id.in_(article_ids))
    rows = db.execute(stmt).all()
    symbol_map: dict[int, list[str]] = defaultdict(list)
    for article_id, symbol in rows:
        symbol_map[int(article_id)].append(str(symbol).upper())
    return symbol_map
