from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        protected_namespaces=("settings_",),
    )

    app_name: str = "NewsEdge"
    environment: str = "dev"
    log_level: str = "INFO"
    cors_origins: str = "http://localhost:5173,http://127.0.0.1:5173"

    database_url: str = "sqlite:///./newsedge.db"
    redis_url: str = "redis://localhost:6379/0"

    alpaca_api_key: str = ""
    alpaca_secret_key: str = ""
    alpaca_news_ws_url: str = "wss://stream.data.alpaca.markets/v2/news"
    alpaca_rest_url: str = "https://data.alpaca.markets/v2"
    alpaca_data_feed: str = "iex"
    default_news_tickers: str = "AAPL,MSFT,NVDA,TSLA"
    enable_web_backfill: bool = True
    web_backfill_sources: str = "reuters.com,cnbc.com,finance.yahoo.com,marketwatch.com,fool.com,investopedia.com,barrons.com"

    sentiment_model: str = "vader"  # finbert | vader
    prediction_horizon_days: int = 5
    model_artifact_path: str = "./artifacts/xgb_recommendation.joblib"
    prediction_min_samples: int = 30
    redis_news_stream: str = "news_stream"
    redis_consumer_group: str = "news_ingestors"
    exclude_mock_news: bool = True
    source_weight_overrides: str = "reuters:1.25,bloomberg:1.25,cnbc:1.1,benzinga:0.95,mock:0.1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
