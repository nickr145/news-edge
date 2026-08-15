from __future__ import annotations

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.services.news_api import backfill_news_api_articles

logger = logging.getLogger(__name__)


class NewsPollingService:
    """Periodically re-runs the Finnhub/Marketaux backfill for subscribed tickers.

    Stands in for continuous stream ingestion: there's no separate worker/consumer
    process deployed, so this keeps news+sentiment from going stale using the same
    synchronous, in-process backfill path subscribe_ticker already uses.
    """

    def __init__(self) -> None:
        self.settings = get_settings()
        self._task: asyncio.Task | None = None
        self._executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="news-poll")

    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    async def _run(self) -> None:
        interval_seconds = self.settings.news_poll_interval_hours * 3600
        while True:
            try:
                await self._poll_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("news poll cycle failed")
            await asyncio.sleep(interval_seconds)

    async def _poll_once(self) -> None:
        from app.services.runtime import news_ingestion

        tickers = await news_ingestion.get_subscribed_tickers()
        loop = asyncio.get_event_loop()

        def _backfill(ticker: str) -> None:
            with SessionLocal() as db:
                backfill_news_api_articles(
                    db,
                    ticker=ticker,
                    days=self.settings.news_poll_days,
                    limit=self.settings.news_poll_limit,
                )

        await asyncio.gather(
            *[loop.run_in_executor(self._executor, _backfill, ticker) for ticker in tickers],
            return_exceptions=True,
        )
