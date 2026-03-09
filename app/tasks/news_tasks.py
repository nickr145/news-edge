from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.article import Article, ArticleTicker
from app.models.sentiment import SentimentScore
from app.services.sentiment import get_sentiment_engine
from app.streams.news_stream import acknowledge_event
from app.tasks.celery_app import celery_app


@celery_app.task(name="newsedge.persist_and_score_event")
def persist_and_score_event(event_id: str, payload: str, model_name: str = "vader") -> dict:
    event = json.loads(payload)
    url = event.get("url")
    if not url:
        acknowledge_event(event_id)
        return {"status": "skipped", "reason": "missing_url"}

    with SessionLocal() as db:
        existing = db.scalar(select(Article).where(Article.url == url))
        if existing:
            acknowledge_event(event_id)
            return {"status": "duplicate", "article_id": existing.id}

        created_at = event.get("created_at") or event.get("published_at")
        published_at = datetime.now(timezone.utc)
        if created_at:
            try:
                published_at = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            except ValueError:
                pass

        article = Article(
            external_id=event.get("id"),
            url=url,
            headline=event.get("headline") or "",
            summary=event.get("summary") or "",
            source=event.get("source") or "",
            published_at=published_at,
            raw_payload=event,
        )
        db.add(article)
        db.flush()

        tickers = [s.upper() for s in (event.get("symbols") or []) if isinstance(s, str)] or ["UNKNOWN"]
        for ticker in tickers:
            db.add(ArticleTicker(article_id=article.id, ticker=ticker))

        sentiment = get_sentiment_engine(model_name).score(article.headline, article.summary)
        for ticker in tickers:
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
        acknowledge_event(event_id)
        return {"status": "ok", "article_id": article.id, "tickers": tickers}
