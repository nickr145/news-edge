from __future__ import annotations

import json
from typing import Any

try:
    import redis
    from redis.asyncio import Redis as AsyncRedis
except Exception:  # pragma: no cover - optional in constrained envs
    redis = None
    AsyncRedis = None

from app.core.config import get_settings

settings = get_settings()


def get_redis_client() -> redis.Redis:
    if redis is None:
        raise RuntimeError("redis library is unavailable")
    return redis.Redis.from_url(settings.redis_url, decode_responses=True)


def ensure_consumer_group() -> bool:
    if redis is None:
        return False
    client = get_redis_client()
    try:
        client.xgroup_create(
            name=settings.redis_news_stream,
            groupname=settings.redis_consumer_group,
            id="$",
            mkstream=True,
        )
        return True
    except redis.exceptions.ResponseError as exc:
        if "BUSYGROUP" not in str(exc):
            raise
        return True
    except redis.exceptions.RedisError:
        return False


async def publish_news_event(event: dict[str, Any]) -> str:
    if AsyncRedis is None:
        return "no-redis"
    client = AsyncRedis.from_url(settings.redis_url, decode_responses=True)
    try:
        event_id = await client.xadd(
            settings.redis_news_stream,
            {"payload": json.dumps(event)},
            maxlen=100_000,
            approximate=True,
        )
        return event_id
    finally:
        await client.aclose()


def consume_news_events(consumer_name: str, count: int = 100, block_ms: int = 5000) -> list[tuple[str, dict[str, str]]]:
    if redis is None:
        return []
    client = get_redis_client()
    entries = client.xreadgroup(
        groupname=settings.redis_consumer_group,
        consumername=consumer_name,
        streams={settings.redis_news_stream: ">"},
        count=count,
        block=block_ms,
    )
    if not entries:
        return []
    _, stream_entries = entries[0]
    return stream_entries


def acknowledge_event(event_id: str) -> None:
    if redis is None:
        return
    client = get_redis_client()
    client.xack(settings.redis_news_stream, settings.redis_consumer_group, event_id)
