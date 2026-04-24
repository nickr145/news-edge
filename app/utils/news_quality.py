from __future__ import annotations

import re
from collections.abc import Iterable

from app.core.config import get_settings


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", (text or "").lower())).strip()


def dedup_key(headline: str, source: str | None = None) -> str:
    base = normalize_text(headline)
    src = normalize_text(source or "")
    return f"{src}|{base}"


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
