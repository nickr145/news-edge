"""Real news API ingestion: Finnhub company-news + Marketaux news search.

Both sources return structured JSON with proper summaries, unlike the Google
News RSS fallback which returns empty summaries. Body scraping is attempted
for each article (with a short timeout) so the body column is populated.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.services.body_scraper import scrape_article_body
from app.services.sentiment import get_sentiment_engine
from app.utils.news_quality import dedup_articles, dedup_key

_MAX_SCRAPE_PER_RUN = 20  # cap body scraping to keep subscribe latency reasonable


# ── Timestamp helpers ────────────────────────────────────────────────────────

def _parse_ts(value: str | int | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(float(value), tz=timezone.utc)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except Exception:
        return datetime.now(timezone.utc)


# ── Finnhub ──────────────────────────────────────────────────────────────────

def _fetch_finnhub(ticker: str, days: int, limit: int) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.finnhub_api_key:
        return []

    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)

    try:
        r = httpx.get(
            "https://finnhub.io/api/v1/company-news",
            params={
                "symbol": ticker,
                "from": start.strftime("%Y-%m-%d"),
                "to": end.strftime("%Y-%m-%d"),
                "token": settings.finnhub_api_key,
            },
            timeout=15,
        )
        r.raise_for_status()
        items = r.json()
        if not isinstance(items, list):
            return []
    except Exception:
        return []

    return [
        {
            "headline": item.get("headline") or "",
            "summary": item.get("summary") or "",
            "url": item.get("url") or "",
            "source": (item.get("source") or "finnhub").lower(),
            "published_at": _parse_ts(item.get("datetime")),
            "provider": "finnhub",
        }
        for item in items[:limit]
        if item.get("url") and item.get("headline")
    ]


# ── Marketaux ────────────────────────────────────────────────────────────────

def _fetch_marketaux(
    ticker: str,
    company_name: str | None,
    days: int,
    limit: int,
) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.marketaux_api_key:
        return []

    published_after = (datetime.now(timezone.utc) - timedelta(days=days)).strftime(
        "%Y-%m-%dT%H:%M:%S"
    )

    try:
        r = httpx.get(
            "https://api.marketaux.com/v1/news/all",
            params={
                "symbols": ticker,
                "api_token": settings.marketaux_api_key,
                "language": "en",
                "sort": "published_desc",
                "limit": min(limit, 100),
                "published_after": published_after,
            },
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
        articles_raw = data.get("data") or []
    except Exception:
        return []

    results = []
    for art in articles_raw:
        title = art.get("title") or ""
        url = art.get("url") or ""
        if not url or not title:
            continue
        results.append(
            {
                "headline": title,
                "summary": art.get("description") or "",
                "url": url,
                "source": (art.get("source") or "marketaux").lower(),
                "published_at": _parse_ts(art.get("published_at")),
                "body": art.get("snippet") or "",
                "provider": "marketaux",
            }
        )
    return results


# ── Main backfill ─────────────────────────────────────────────────────────────

def backfill_news_api_articles(
    db: Session,
    ticker: str,
    company_name: str | None = None,
    days: int = 30,
    limit: int = 100,
    sentiment_model: str | None = None,
) -> int:
    """Fetch from Finnhub + Marketaux, deduplicate, scrape bodies, persist."""
    settings = get_settings()
    ticker = ticker.upper()
    sentiment_model = sentiment_model or settings.sentiment_model

    finnhub_items = _fetch_finnhub(ticker, days=days, limit=limit)
    marketaux_items = _fetch_marketaux(ticker, company_name=company_name, days=days, limit=limit)

    all_items = dedup_articles(finnhub_items + marketaux_items)

    # Pre-filter: only keep articles that actually mention the ticker or company.
    ticker_lower = ticker.lower()
    company_lower = (company_name or "").lower()

    def _relevant(row: dict) -> bool:
        text = (row["headline"] + " " + (row.get("summary") or "")).lower()
        return ticker_lower in text or bool(company_lower and company_lower in text)

    all_items = [r for r in all_items if _relevant(r)]
    if not all_items:
        return 0

    # Bulk dedup check against DB
    since = datetime.now(timezone.utc) - timedelta(days=60)
    existing_sigs: set[str] = {
        dedup_key(h or "", s)
        for h, s in db.execute(
            select(Article.headline, Article.source).where(Article.published_at >= since)
        ).all()
    }
    candidate_urls = [r["url"] for r in all_items]
    existing_urls: set[str] = {
        r[0]
        for r in db.execute(select(Article.url).where(Article.url.in_(candidate_urls))).all()
    }

    engine = get_sentiment_engine(sentiment_model)
    texts = [(r["headline"], r.get("summary") or "") for r in all_items]
    sentiments = engine.score_many(texts) if texts else []

    inserted = 0
    scrape_count = 0

    for row, sentiment in zip(all_items, sentiments, strict=False):
        sig = dedup_key(row["headline"], row.get("source"))
        if sig in existing_sigs or row["url"] in existing_urls:
            continue

        # Body: use what we already have, then try scraping if enabled.
        body = row.get("body") or ""
        if (
            not body
            and settings.enable_body_scraping
            and scrape_count < _MAX_SCRAPE_PER_RUN
        ):
            body = scrape_article_body(row["url"], timeout=settings.body_scrape_timeout)
            scrape_count += 1

        article = Article(
            external_id=None,
            url=row["url"],
            headline=row["headline"],
            summary=row.get("summary") or "",
            body=body or None,
            source=row.get("source") or row.get("provider") or "unknown",
            published_at=row["published_at"],
            raw_payload={"provider": row.get("provider", "news-api"), **{
                k: v for k, v in row.items() if k not in ("published_at",)
            }},
        )
        db.add(article)
        db.flush()

        db.add(ArticleTicker(article_id=article.id, ticker=ticker))
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
        existing_sigs.add(sig)
        existing_urls.add(row["url"])
        inserted += 1

    if inserted:
        db.commit()

    return inserted
