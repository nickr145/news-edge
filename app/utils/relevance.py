from __future__ import annotations


def compute_ticker_relevance(ticker: str, headline: str, summary: str, symbols: list[str]) -> float:
    ticker = (ticker or "").upper()
    headline_l = (headline or "").lower()
    summary_l = (summary or "").lower()
    symbols_u = [s.upper() for s in (symbols or [])]

    score = 0.0

    if ticker in symbols_u:
        score += 0.45

    if ticker.lower() in headline_l:
        score += 0.35

    if ticker.lower() in summary_l:
        score += 0.15

    # Penalize broad basket articles tagged with many symbols.
    if symbols_u:
        score -= min(0.25, 0.04 * max(len(symbols_u) - 1, 0))

    # Small boost when ticker appears in URL slug.
    if ticker.lower() in (headline_l + " " + summary_l):
        score += 0.05

    return max(0.0, min(1.0, score))
