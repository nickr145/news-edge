from __future__ import annotations

from datetime import datetime, timedelta, timezone

from collections import defaultdict

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.schemas.news import ArticleOut, SentimentSummaryOut, SentimentTrendOut, SentimentTrendPoint
from app.utils.news_quality import dedup_key, source_weight
from app.utils.relevance import compute_ticker_relevance
from app.utils.stats import ewma, mean, std


def get_articles_for_ticker(
    db: Session,
    ticker: str,
    limit: int = 50,
    offset: int = 0,
    days: int | None = None,
    min_relevance: float = 0.35,
    include_mock: bool = False,
) -> list[ArticleOut]:
    ticker = ticker.upper()
    since = None
    if days is not None:
        since = datetime.now(timezone.utc) - timedelta(days=days)

    # Overfetch so Python-side dedup/relevance filtering doesn't under-deliver vs. the requested limit.
    db_limit = max(limit * 4, 400)
    stmt = (
        select(Article, SentimentScore)
        .join(ArticleTicker, ArticleTicker.article_id == Article.id)
        .outerjoin(
            SentimentScore,
            (SentimentScore.article_id == Article.id) & (SentimentScore.ticker == ticker),
        )
        .where(ArticleTicker.ticker == ticker)
        .order_by(Article.published_at.desc())
        .limit(db_limit)
        .offset(offset)
    )
    if since is not None:
        stmt = stmt.where(Article.published_at >= since)
    if not include_mock:
        stmt = stmt.where((Article.source.is_(None)) | (Article.source != "mock"))

    rows = db.execute(stmt).all()
    article_ids = [article.id for article, _ in rows]
    symbol_map = _load_symbol_map(db, article_ids)
    seen: set[str] = set()
    out: list[ArticleOut] = []
    for article, sentiment in rows:
        if len(out) >= limit:
            break
        key = dedup_key(article.headline or "", article.source)
        if key in seen:
            continue
        seen.add(key)
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=article.headline or "",
            summary=article.summary or "",
            symbols=symbol_map.get(article.id, []),
        )
        if relevance < min_relevance:
            continue
        weight = source_weight(article.source)
        payload = article.raw_payload or {}
        out.append(
            ArticleOut(
                id=article.id,
                url=article.url,
                headline=article.headline,
                summary=article.summary,
                body=article.body,
                source=article.source,
                published_at=article.published_at,
                sentiment_label=sentiment.label if sentiment else None,
                compound=float(sentiment.compound) if sentiment else None,
                relevance_score=float(round(relevance, 4)),
                source_weight=float(round(weight, 4)),
                near_earnings=payload.get("near_earnings") or None,
                is_sec_filing=payload.get("is_sec_filing") or None,
            )
        )
    return out


def get_sentiment_summary(
    db: Session,
    ticker: str,
    days: int = 7,
    min_relevance: float = 0.35,
    include_mock: bool = False,
) -> SentimentSummaryOut:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(days=days)
    stmt = (
        select(
            SentimentScore.article_id,
            SentimentScore.compound,
            SentimentScore.label,
            Article.headline,
            Article.summary,
            Article.source,
        )
        .join(Article, Article.id == SentimentScore.article_id)
        .where(SentimentScore.ticker == ticker)
        .where(SentimentScore.scored_at >= since)
        .order_by(SentimentScore.scored_at.asc())
    )
    if not include_mock:
        stmt = stmt.where((Article.source.is_(None)) | (Article.source != "mock"))
    rows = db.execute(stmt).all()
    article_ids = [int(r[0]) for r in rows]
    symbol_map = _load_symbol_map(db, article_ids)

    weighted_compounds: list[float] = []
    labels: dict[str, int] = {"POSITIVE": 0, "NEUTRAL": 0, "NEGATIVE": 0}
    seen: set[str] = set()
    for article_id, compound, label, headline, summary, src in rows:
        key = dedup_key(headline or "", src)
        if key in seen:
            continue
        seen.add(key)
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=headline or "",
            summary=summary or "",
            symbols=symbol_map.get(int(article_id), []),
        )
        if relevance < min_relevance:
            continue
        weighted_compounds.append(float(compound) * source_weight(src))
        labels[label] = labels.get(label, 0) + 1

    return SentimentSummaryOut(
        ticker=ticker,
        count=len(weighted_compounds),
        mean_compound=mean(weighted_compounds),
        std_compound=std(weighted_compounds),
        ewma_compound=ewma(weighted_compounds),
        label_distribution=labels,
    )


def get_sentiment_trend(
    db: Session,
    ticker: str,
    hours: int = 72,
    min_relevance: float = 0.35,
    include_mock: bool = False,
) -> SentimentTrendOut:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(hours=hours)

    stmt = (
        select(
            SentimentScore.article_id,
            Article.published_at,
            SentimentScore.compound,
            Article.headline,
            Article.summary,
            Article.source,
        )
        .join(Article, Article.id == SentimentScore.article_id)
        .where(SentimentScore.ticker == ticker)
        .where(Article.published_at >= since)
        .order_by(Article.published_at.asc())
    )
    if not include_mock:
        stmt = stmt.where((Article.source.is_(None)) | (Article.source != "mock"))
    rows = db.execute(stmt).all()
    article_ids = [int(r[0]) for r in rows]
    symbol_map = _load_symbol_map(db, article_ids)

    buckets: dict[datetime, list[float]] = defaultdict(list)
    seen: set[str] = set()
    for article_id, published_at, compound, headline, summary, src in rows:
        key = dedup_key(headline or "", src)
        if key in seen:
            continue
        seen.add(key)
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=headline or "",
            summary=summary or "",
            symbols=symbol_map.get(int(article_id), []),
        )
        if relevance < min_relevance:
            continue
        dt = published_at.replace(hour=0, minute=0, second=0, microsecond=0)
        buckets[dt].append(float(compound) * source_weight(src))

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


def get_source_breakdown(
    db: Session,
    ticker: str,
    days: int = 30,
    min_relevance: float = 0.35,
    include_mock: bool = False,
) -> list[dict[str, int | str]]:
    ticker = ticker.upper()
    since = datetime.now(timezone.utc) - timedelta(days=days)
    stmt = (
        select(Article.id, Article.headline, Article.summary, Article.source)
        .join(ArticleTicker, ArticleTicker.article_id == Article.id)
        .where(ArticleTicker.ticker == ticker)
        .where(Article.published_at >= since)
    )
    if not include_mock:
        stmt = stmt.where((Article.source.is_(None)) | (Article.source != "mock"))

    rows = db.execute(stmt).all()
    article_ids = [int(row[0]) for row in rows]
    symbol_map = _load_symbol_map(db, article_ids)
    seen: set[str] = set()
    counts: dict[str, int] = defaultdict(int)
    for article_id, headline, summary, source in rows:
        key = dedup_key(headline or "", source)
        if key in seen:
            continue
        seen.add(key)
        relevance = compute_ticker_relevance(
            ticker=ticker,
            headline=headline or "",
            summary=summary or "",
            symbols=symbol_map.get(int(article_id), []),
        )
        if relevance < min_relevance:
            continue
        counts[str(source or "unknown")] += 1

    return [
        {"source": source, "count": count}
        for source, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    ]
