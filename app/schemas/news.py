from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ArticleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    url: str
    headline: str
    summary: str | None
    body: str | None = None
    source: str | None
    published_at: datetime
    sentiment_label: str | None = None
    compound: float | None = None
    relevance_score: float | None = None
    source_weight: float | None = None
    near_earnings: bool | None = None
    is_sec_filing: bool | None = None


class SentimentSummaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    ticker: str
    count: int
    mean_compound: float
    std_compound: float
    ewma_compound: float
    label_distribution: dict[str, int]


class SentimentTrendPoint(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    bucket: datetime
    mean_compound: float
    article_count: int


class SentimentTrendOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    ticker: str
    points: list[SentimentTrendPoint]
