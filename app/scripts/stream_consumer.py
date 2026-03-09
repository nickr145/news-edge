from __future__ import annotations

from app.core.config import get_settings
from app.streams.news_stream import consume_news_events, ensure_consumer_group
from app.tasks.news_tasks import persist_and_score_event


def main() -> None:
    settings = get_settings()
    ensure_consumer_group()
    consumer_name = "consumer-1"

    while True:
        entries = consume_news_events(consumer_name=consumer_name, count=100, block_ms=5000)
        if not entries:
            continue

        for event_id, fields in entries:
            payload = fields.get("payload")
            if not payload:
                continue
            persist_and_score_event.delay(event_id, payload, settings.sentiment_model)


if __name__ == "__main__":
    main()
