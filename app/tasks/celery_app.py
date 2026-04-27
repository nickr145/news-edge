from celery import Celery
from celery.schedules import crontab

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
    beat_schedule={
        # Refresh price labels daily at 1:00 UTC (markets closed, bars are final).
        "refresh-price-labels-daily": {
            "task": "newsedge.refresh_price_labels",
            "schedule": crontab(hour=1, minute=0),
        },
        # Retrain prediction model weekly on Monday at 3:00 UTC
        # (after price labels have been refreshed the night before).
        "retrain-models-weekly": {
            "task": "newsedge.retrain_models",
            "schedule": crontab(day_of_week=1, hour=3, minute=0),
        },
    },
)
