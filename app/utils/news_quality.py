from __future__ import annotations

import re
from collections.abc import Iterable

from app.core.config import get_settings


_SOURCE_SUFFIX_RE = re.compile(r'\s*[-–|]\s*[A-Za-z][\w\s\.&]{1,40}$')


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", (text or "").lower())).strip()


def _strip_source_suffix(headline: str) -> str:
    """Remove trailing publisher attribution like '- Yahoo Finance' or '| Reuters'."""
    return _SOURCE_SUFFIX_RE.sub('', headline).strip()


def dedup_key(headline: str, source: str | None = None) -> str:
    return normalize_text(_strip_source_suffix(headline))


def source_weight(source: str | None) -> float:
    settings = get_settings()
    source_key = normalize_text(source or "")
    mapping: dict[str, float] = {}
    for item in settings.source_weight_overrides.split(","):
        if ":" not in item:
            continue
        key, value = item.split(":", 1)
        key = normalize_text(key)
        try:
            mapping[key] = float(value)
        except ValueError:
            continue
    return mapping.get(source_key, 1.0)


def dedup_articles(items: Iterable[dict]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for item in items:
        key = dedup_key(item.get("headline", ""), item.get("source"))
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out
