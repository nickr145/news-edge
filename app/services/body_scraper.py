"""Scrape full article body text from a URL using httpx + BeautifulSoup.

Only called for sources that publish accessible URLs (Finnhub, NewsAPI).
Google News RSS links often hit paywalls immediately, so web_backfill skips this.
"""
from __future__ import annotations

import httpx

# Try content containers in order of specificity.
_SELECTORS = [
    "article",
    '[role="main"]',
    ".article-body",
    ".article-content",
    ".story-body",
    ".post-content",
    ".entry-content",
    ".content-body",
    ".page-content",
    "main",
]

_STRIP_TAGS = {
    "script", "style", "nav", "footer", "aside", "header",
    "noscript", "figure", "figcaption", "iframe", "form",
}

_MAX_CHARS = 4000
_MIN_CHARS = 120

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; NewsEdge/1.0; +https://github.com/newsedge)"
    ),
    "Accept": "text/html,application/xhtml+xml",
}


def scrape_article_body(url: str, timeout: int = 6) -> str:
    """Return up to 4 000 chars of main body text, or '' on any failure."""
    try:
        from bs4 import BeautifulSoup
    except ImportError:
        return ""

    try:
        with httpx.Client(timeout=timeout, follow_redirects=True, headers=_HEADERS) as client:
            r = client.get(url)
            r.raise_for_status()
            ct = r.headers.get("content-type", "")
            if "text/html" not in ct and "application/xhtml" not in ct:
                return ""
            html = r.text
    except Exception:
        return ""

    soup = BeautifulSoup(html, "lxml")
    for tag in soup(_STRIP_TAGS):
        tag.decompose()

    for selector in _SELECTORS:
        el = soup.select_one(selector)
        if el:
            text = " ".join(el.get_text(" ", strip=True).split())
            if len(text) >= _MIN_CHARS:
                return text[:_MAX_CHARS]

    # Fallback: full page text
    text = " ".join(soup.get_text(" ", strip=True).split())
    return text[:_MAX_CHARS] if len(text) >= _MIN_CHARS else ""
