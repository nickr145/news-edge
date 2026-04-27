"""SEC EDGAR ingestion for 8-K, 10-K, and 10-Q filings.

Uses only the free, unauthenticated EDGAR REST API:
  - https://www.sec.gov/files/company_tickers.json  → ticker → CIK mapping
  - https://data.sec.gov/submissions/CIK{cik}.json  → filing history

Each matching filing is turned into an Article (source="sec-edgar") so it
flows through the sentiment pipeline like any other news item, and is also
recorded in the sec_filings table for structured queries.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.article import Article, ArticleTicker
from app.models.sec_filing import SecFiling
from app.models.sentiment import SentimentScore
from app.services.sentiment import get_sentiment_engine
from app.utils.news_quality import dedup_key

_EDGAR_HEADERS = {
    "User-Agent": "NewsEdge research-bot contact@newsedge.example.com",
    "Accept": "application/json",
}
_TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
_SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik}.json"

# Module-level cache: populated once per process lifetime.
_cik_cache: dict[str, str] = {}  # TICKER → zero-padded 10-digit CIK


def _load_cik_map(client: httpx.Client) -> dict[str, str]:
    if _cik_cache:
        return _cik_cache
    try:
        r = client.get(_TICKERS_URL, timeout=20)
        r.raise_for_status()
        for entry in r.json().values():
            ticker = str(entry.get("ticker") or "").upper()
            cik = str(entry.get("cik_str") or entry.get("cik") or "")
            if ticker and cik:
                _cik_cache[ticker] = cik.zfill(10)
    except Exception:
        pass
    return _cik_cache


def _get_cik(ticker: str, client: httpx.Client) -> str | None:
    return _load_cik_map(client).get(ticker.upper())


def _filing_index_url(cik_raw: str, accession_formatted: str) -> str:
    """Build the EDGAR filing-index HTML URL from CIK and accession number."""
    cik_int = str(int(cik_raw))  # drop leading zeros for the path
    acc_nodashes = accession_formatted.replace("-", "")
    return (
        f"https://www.sec.gov/Archives/edgar/data/"
        f"{cik_int}/{acc_nodashes}/{accession_formatted}-index.htm"
    )


def _format_accession(raw: str) -> str:
    """Normalise accession number to the 'XXXXXXXXXX-YY-NNNNNN' dash form."""
    clean = raw.replace("-", "").replace(" ", "")
    if len(clean) == 18:
        return f"{clean[:10]}-{clean[10:12]}-{clean[12:]}"
    return raw  # already formatted or unknown shape


def backfill_sec_filings(
    db: Session,
    ticker: str,
    days: int = 365,
    limit: int = 30,
    sentiment_model: str | None = None,
) -> int:
    """Fetch recent 8-K / 10-K / 10-Q filings from EDGAR and persist them.

    Returns the count of new filings stored.
    """
    settings = get_settings()
    ticker = ticker.upper()
    sentiment_model = sentiment_model or settings.sentiment_model
    target_forms: set[str] = {
        f.strip().upper()
        for f in settings.sec_filing_forms.split(",")
        if f.strip()
    }
    since = datetime.now(timezone.utc) - timedelta(days=days)

    with httpx.Client(headers=_EDGAR_HEADERS, timeout=20, follow_redirects=True) as client:
        cik = _get_cik(ticker, client)
        if not cik:
            return 0

        try:
            r = client.get(_SUBMISSIONS_URL.format(cik=cik))
            r.raise_for_status()
            submissions = r.json()
        except Exception:
            return 0

        recent = submissions.get("filings", {}).get("recent", {})
        accession_list: list[str] = recent.get("accessionNumber") or []
        form_list: list[str] = recent.get("form") or []
        date_list: list[str] = recent.get("filingDate") or []
        desc_list: list[str] = recent.get("primaryDocument") or []

        company_name: str = submissions.get("name") or ticker

        # Existing accession numbers for this ticker (avoid re-insert)
        existing_accessions: set[str] = {
            r[0]
            for r in db.execute(
                select(SecFiling.accession_number).where(SecFiling.ticker == ticker)
            ).all()
        }

        engine = get_sentiment_engine(sentiment_model)
        inserted = 0

        for acc_raw, form, filed_str, desc in zip(
            accession_list, form_list, date_list, desc_list
        ):
            if inserted >= limit:
                break
            if form not in target_forms:
                continue

            acc = _format_accession(acc_raw)
            if acc in existing_accessions:
                continue

            try:
                filed_dt = datetime.strptime(filed_str, "%Y-%m-%d").replace(
                    tzinfo=timezone.utc
                )
            except Exception:
                continue

            if filed_dt < since:
                # Filings are returned newest-first; once we go past the
                # cutoff, the rest will be even older.
                break

            filing_url = _filing_index_url(cik, acc)
            headline = f"SEC {form}: {company_name}"
            summary = f"{company_name} filed a {form} with the SEC on {filed_str}."

            # Check whether we already have an article for this URL.
            existing_article = db.scalar(select(Article).where(Article.url == filing_url))
            article_id: int | None = None

            if not existing_article:
                sig = dedup_key(headline, "sec-edgar")
                sentiment = engine.score(headline, summary)
                article = Article(
                    external_id=acc,
                    url=filing_url,
                    headline=headline,
                    summary=summary,
                    source="sec-edgar",
                    published_at=filed_dt,
                    raw_payload={
                        "provider": "sec-edgar",
                        "form_type": form,
                        "cik": cik,
                        "accession_number": acc,
                        "company_name": company_name,
                        "is_sec_filing": True,
                    },
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
                article_id = article.id
            else:
                article_id = existing_article.id

            db.add(
                SecFiling(
                    ticker=ticker,
                    cik=cik,
                    accession_number=acc,
                    form_type=form,
                    filed_at=filed_dt,
                    description=desc or form,
                    filing_url=filing_url,
                    article_id=article_id,
                )
            )
            existing_accessions.add(acc)
            inserted += 1

        if inserted:
            db.commit()

    return inserted
