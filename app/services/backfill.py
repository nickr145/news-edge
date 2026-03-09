from __future__ import annotations

from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.services.sentiment import get_sentiment_engine


def _parse_timestamp(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.now(timezone.utc)


def _to_rfc3339(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def backfill_news_for_ticker(db: Session, ticker: str, days: int = 30, limit: int = 200) -> int:
    settings = get_settings()
    if not settings.alpaca_api_key or not settings.alpaca_secret_key:
        return 0

    ticker = ticker.upper()
    start = datetime.now(timezone.utc) - timedelta(days=days)
    end = datetime.now(timezone.utc)
    headers = {
        "APCA-API-KEY-ID": settings.alpaca_api_key,
        "APCA-API-SECRET-KEY": settings.alpaca_secret_key,
    }

    url = "https://data.alpaca.markets/v1beta1/news"
    inserted = 0
    engine = get_sentiment_engine(settings.sentiment_model)
    remaining = min(max(limit, 1), 1000)
    page_token: str | None = None
    per_page = min(50, remaining)

    with httpx.Client(timeout=20) as client:
        while remaining > 0:
            params = {
                "symbols": ticker,
                "start": _to_rfc3339(start),
                "end": _to_rfc3339(end),
                "limit": min(per_page, remaining),
                "sort": "desc",
            }
            if page_token:
                params["page_token"] = page_token

            response = client.get(url, params=params, headers=headers)
            if response.status_code >= 400:
                raise RuntimeError(f"Alpaca backfill failed [{response.status_code}]: {response.text}")

            payload = response.json()
            news_rows = payload.get("news", [])
            if not news_rows:
                break

            for item in news_rows:
                article_url = item.get("url")
                if not article_url:
                    continue

                existing = db.scalar(select(Article).where(Article.url == article_url))
                if existing:
                    continue

                article = Article(
                    external_id=str(item.get("id")) if item.get("id") is not None else None,
                    url=article_url,
                    headline=item.get("headline") or "",
                    summary=item.get("summary") or "",
                    source=item.get("source") or "",
                    published_at=_parse_timestamp(item.get("created_at")),
                    raw_payload=item,
                )
                db.add(article)
                db.flush()

                symbols = [s.upper() for s in (item.get("symbols") or []) if isinstance(s, str)]
                if not symbols:
                    symbols = [ticker]
                for symbol in symbols:
                    db.add(ArticleTicker(article_id=article.id, ticker=symbol))

                sentiment = engine.score(article.headline, article.summary)
                for symbol in symbols:
                    db.add(
                        SentimentScore(
                            article_id=article.id,
                            ticker=symbol,
                            model=sentiment.model,
                            score_positive=sentiment.score_positive,
                            score_negative=sentiment.score_negative,
                            score_neutral=sentiment.score_neutral,
                            compound=sentiment.compound,
                            label=sentiment.label,
                        )
                    )

                inserted += 1

            remaining -= len(news_rows)
            page_token = payload.get("next_page_token")
            if not page_token:
                break

    if inserted:
        db.commit()

    return inserted
