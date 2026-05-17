"""Remove duplicate articles caused by trailing source suffixes in headlines.

Keeps the article with the most content (body > summary length), falling back
to the earlier ingested_at. Deletes losers via CASCADE (article_tickers,
sentiment_scores removed automatically).

Run:
    python -m app.scripts.dedup_articles
"""
from __future__ import annotations

import re
from collections import defaultdict

from sqlalchemy import create_engine, delete, select, text
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.article import Article

_SOURCE_SUFFIX_RE = re.compile(r'\s*[-–|]\s*[A-Za-z][\w\s\.&]{1,40}$')


def _normalize(headline: str) -> str:
    stripped = _SOURCE_SUFFIX_RE.sub('', headline).strip()
    lowered = stripped.lower()
    cleaned = re.sub(r'[^a-z0-9 ]', ' ', lowered)
    return re.sub(r'\s+', ' ', cleaned).strip()


def _score(article: Article) -> int:
    """Higher is better — prefer articles with more content."""
    return len(article.body or '') * 3 + len(article.summary or '')


def main() -> None:
    settings = get_settings()
    engine = create_engine(settings.database_url)

    with Session(engine) as db:
        articles = db.execute(select(Article)).scalars().all()
        print(f"Total articles: {len(articles)}")

        # Group by normalized headline
        groups: dict[str, list[Article]] = defaultdict(list)
        for a in articles:
            key = _normalize(a.headline)
            groups[key].append(a)

        duplicate_groups = {k: v for k, v in groups.items() if len(v) > 1}
        print(f"Duplicate groups found: {len(duplicate_groups)}")

        ids_to_delete: list[int] = []
        for key, group in duplicate_groups.items():
            # Sort: best content first, then earliest ingested
            group.sort(key=lambda a: (-_score(a), a.ingested_at))
            keeper = group[0]
            losers = group[1:]
            print(f"  KEEP [{keeper.id}] {keeper.headline[:80]}")
            for loser in losers:
                print(f"  DROP [{loser.id}] {loser.headline[:80]}")
                ids_to_delete.append(loser.id)

        if not ids_to_delete:
            print("Nothing to delete.")
            return

        print(f"\nDeleting {len(ids_to_delete)} duplicate articles...")
        db.execute(delete(Article).where(Article.id.in_(ids_to_delete)))
        db.commit()
        print("Done.")


if __name__ == "__main__":
    main()
