from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote_plus
import xml.etree.ElementTree as ET

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.services.sentiment import get_sentiment_engine
from app.utils.news_quality import dedup_articles, dedup_key


def _parse_pub_date(value: str) -> datetime:
    try:
        return datetime.strptime(value, "%a, %d %b %Y %H:%M:%S %Z").replace(tzinfo=timezone.utc)
    except Exception:
        return datetime.now(timezone.utc)


def _serialize_row(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    published_at = out.get("published_at")
    if isinstance(published_at, datetime):
        out["published_at"] = published_at.isoformat()
    return out


def _build_queries(ticker: str, company_name: str | None) -> list[str]:
    settings = get_settings()
    sources = [source.strip() for source in settings.web_backfill_sources.split(",") if source.strip()]

    company_terms: list[str] = [ticker]
    if company_name:
        company_terms.append(company_name)
    base_clause = " OR ".join(dict.fromkeys(company_terms))

    queries = [f"({base_clause}) stock"]
    queries.extend(f"({base_clause}) site:{source}" for source in sources)
    return queries


def _fetch_feed_items(client: httpx.Client, query: str, days: int, limit: int) -> list[dict[str, Any]]:
    url = f"https://news.google.com/rss/search?q={quote_plus(query)}&hl=en-US&gl=US&ceid=US:en"
    response = client.get(url)
    response.raise_for_status()
    root = ET.fromstring(response.text)
    channel = root.find("channel")
    if channel is None:
        return []

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    items: list[dict[str, Any]] = []
    for item in channel.findall("item")[: max(1, min(limit, 100))]:
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        pub_date = (item.findtext("pubDate") or "").strip()
        source = (item.findtext("source") or "google-news").strip().lower()
        if not title or not link:
            continue

        published_at = _parse_pub_date(pub_date)
        if published_at < cutoff:
            continue

        items.append(
            {
                "headline": title,
                "summary": "",
                "url": link,
                "source": source,
                "published_at": published_at,
                "query": query,
            }
        )
    return items


def backfill_web_news_for_ticker(
    db: Session,
    ticker: str,
    company_name: str | None = None,
    days: int = 30,
    limit: int = 100,
    sentiment_model: str | None = None,
) -> int:
    ticker = ticker.upper()
    sentiment_model = sentiment_model or get_settings().sentiment_model
    queries = _build_queries(ticker, company_name)

    with httpx.Client(timeout=20, follow_redirects=True) as client:
        collected: list[dict[str, Any]] = []
        per_query_limit = max(10, min(50, limit // max(len(queries), 1) + 5))
        for query in queries:
            try:
                collected.extend(_fetch_feed_items(client, query=query, days=days, limit=per_query_limit))
            except Exception:
                continue

    deduped = dedup_articles(collected)
    # Keep diverse sources instead of letting one outlet dominate.
    source_counts: Counter[str] = Counter()
    selected: list[dict[str, Any]] = []
    for row in sorted(deduped, key=lambda item: item["published_at"], reverse=True):
        source = str(row.get("source") or "unknown")
        if source_counts[source] >= max(5, limit // 6):
            continue
        selected.append(row)
        source_counts[source] += 1
        if len(selected) >= limit:
            break

    if not selected:
        return 0

    # Drop articles with no text mention of the ticker or company name.
    # Web backfill artificially tags everything with the queried ticker, so we
    # pre-filter here to avoid storing unrelated articles from broad RSS feeds.
    ticker_lower = ticker.lower()
    company_lower = (company_name or "").lower()

    def _has_text_signal(row: dict) -> bool:
        text = (row["headline"] + " " + (row.get("summary") or "")).lower()
        return ticker_lower in text or bool(company_lower and company_lower in text)

    selected = [row for row in selected if _has_text_signal(row)]
    if not selected:
        return 0

    # Build existing-signature set once (avoids O(n²) per-article DB queries).
    since = datetime.now(timezone.utc) - timedelta(days=60)
    existing_rows = db.execute(
        select(Article.headline, Article.source).where(Article.published_at >= since)
    ).all()
    existing_sigs: set[str] = {dedup_key(h or "", s) for h, s in existing_rows}

    # Batch URL existence check for the candidate set.
    candidate_urls = [row["url"] for row in selected]
    existing_url_rows = db.execute(select(Article.url).where(Article.url.in_(candidate_urls))).all()
    existing_urls: set[str] = {r[0] for r in existing_url_rows}

    engine = get_sentiment_engine(sentiment_model)
    texts = [(row["headline"], row.get("summary") or "") for row in selected]
    sentiments = engine.score_many(texts) if texts else []

    inserted = 0
    for row, sentiment in zip(selected, sentiments, strict=False):
        sig = dedup_key(row["headline"], row.get("source"))
        if sig in existing_sigs:
            continue
        if row["url"] in existing_urls:
            continue

        article = Article(
            external_id=None,
            url=row["url"],
            headline=row["headline"],
            summary=row.get("summary") or "",
            source=row.get("source") or "google-news",
            published_at=row["published_at"],
            raw_payload={"provider": "multi-source-google-news-rss", **_serialize_row(row)},
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
