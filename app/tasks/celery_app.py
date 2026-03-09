from celery import Celery

from app.core.config import get_settings

settings = get_settings()

celery_app = Celery(
    "newsedge",
    broker=settings.redis_url,
    backend=settings.redis_url,
    include=["app.tasks.news_tasks", "app.tasks.prediction_tasks"],
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
)
