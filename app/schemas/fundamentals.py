from datetime import datetime

from pydantic import BaseModel, ConfigDict


class EarningsEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ticker: str
    report_date: datetime
    fiscal_date_ending: str | None
    estimated_eps: float | None
    actual_eps: float | None
    surprise_pct: float | None


class SecFilingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ticker: str
    form_type: str
    filed_at: datetime
    description: str | None
    filing_url: str
    article_id: int | None
