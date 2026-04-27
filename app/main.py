from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes_fundamentals import router as fundamentals_router
from app.api.routes_health import router as health_router
from app.api.routes_news import router as news_router
from app.api.routes_price import router as price_router
from app.api.routes_prediction import router as prediction_router
from app.api.routes_ws import router as ws_router
from app.core.config import get_settings
from app.db.init_db import init_db
from app.services.runtime import news_ingestion
from app.streams.news_stream import ensure_consumer_group

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    ensure_consumer_group()
    await news_ingestion.start()
    yield
    await news_ingestion.stop()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(health_router)
app.include_router(news_router)
app.include_router(price_router)
app.include_router(prediction_router)
app.include_router(fundamentals_router)
app.include_router(ws_router)
