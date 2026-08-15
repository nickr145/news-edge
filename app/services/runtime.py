from app.services.ingestion import AlpacaNewsIngestionService
from app.services.poller import NewsPollingService

news_ingestion = AlpacaNewsIngestionService()
news_poller = NewsPollingService()
