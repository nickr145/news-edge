from __future__ import annotations

import asyncio
import json
from typing import Any

from app.core.config import get_settings
from app.streams.news_stream import publish_news_event


class AlpacaNewsIngestionService:
    def __init__(self) -> None:
        self.settings = get_settings()
        self._running = False
        self._task: asyncio.Task | None = None
        self._tickers: set[str] = set()
        self._tickers_lock = asyncio.Lock()
        self._resubscribe_event = asyncio.Event()

    async def start(self, default_tickers: list[str] | None = None) -> None:
        if self._running:
            return
        self._running = True
        initial_tickers = default_tickers or [
            ticker.strip().upper()
            for ticker in self.settings.default_news_tickers.split(",")
            if ticker.strip()
        ]
        async with self._tickers_lock:
            self._tickers.update(initial_tickers)
        self._task = asyncio.create_task(self._run())

    async def subscribe_ticker(self, ticker: str) -> list[str]:
        clean = ticker.strip().upper()
        if not clean:
            return await self.get_subscribed_tickers()
        async with self._tickers_lock:
            self._tickers.add(clean)
        self._resubscribe_event.set()
        return await self.get_subscribed_tickers()

    async def get_subscribed_tickers(self) -> list[str]:
        async with self._tickers_lock:
            return sorted(self._tickers)

    async def stop(self) -> None:
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        if not self.settings.alpaca_api_key or not self.settings.alpaca_secret_key:
            return

        try:
            import websockets
        except Exception:
            return

        while self._running:
            try:
                async with websockets.connect(self.settings.alpaca_news_ws_url) as ws:
                    await ws.send(
                        json.dumps(
                            {
                                "action": "auth",
                                "key": self.settings.alpaca_api_key,
                                "secret": self.settings.alpaca_secret_key,
                            }
                        )
                    )
                    self._resubscribe_event.clear()
                    await self._send_subscribe(ws)

                    while self._running:
                        if self._resubscribe_event.is_set():
                            self._resubscribe_event.clear()
                            await self._send_subscribe(ws)

                        try:
                            message = await asyncio.wait_for(ws.recv(), timeout=1.0)
                        except asyncio.TimeoutError:
                            continue

                        payload = json.loads(message)
                        if isinstance(payload, list):
                            for item in payload:
                                await self._handle_event(item)
                        elif isinstance(payload, dict):
                            await self._handle_event(payload)
            except asyncio.CancelledError:
                break
            except Exception:
                await asyncio.sleep(3)

    async def _send_subscribe(self, ws) -> None:
        async with self._tickers_lock:
            tickers = sorted(self._tickers)
        if not tickers:
            return
        await ws.send(json.dumps({"action": "subscribe", "news": tickers}))

    async def _handle_event(self, event: dict[str, Any]) -> None:
        if not isinstance(event, dict):
            return
        if event.get("T") not in {"n", "news"} and "headline" not in event:
            return
        await publish_news_event(event)
