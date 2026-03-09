import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.db.session import SessionLocal
from app.services.analytics import get_articles_for_ticker

router = APIRouter(tags=["ws"])


@router.websocket("/ws/news/{ticker}")
async def news_stream(websocket: WebSocket, ticker: str):
    await websocket.accept()
    last_seen_id = 0

    try:
        while True:
            # Use a short-lived DB session per loop to avoid stale connections.
            with SessionLocal() as db:
                rows = get_articles_for_ticker(db, ticker=ticker, limit=20, offset=0)

            new_rows = [r for r in rows if r.id > last_seen_id]
            for row in sorted(new_rows, key=lambda r: r.id):
                await websocket.send_json(row.model_dump(mode="json"))
                last_seen_id = max(last_seen_id, row.id)

            await asyncio.sleep(2)
    except WebSocketDisconnect:
        return
