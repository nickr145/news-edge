from fastapi.testclient import TestClient

from app.db.init_db import init_db
from app.db.session import SessionLocal
from app.main import app
from app.models.article import Article, ArticleTicker
from app.models.earnings import EarningsEvent
from app.models.prediction import Prediction
from app.models.sec_filing import SecFiling
from app.models.sentiment import SentimentScore


def _reset_db() -> None:
    init_db()
    with SessionLocal() as db:
        db.query(SentimentScore).delete()
        db.query(SecFiling).delete()
        db.query(ArticleTicker).delete()
        db.query(EarningsEvent).delete()
        db.query(Prediction).delete()
        db.query(Article).delete()
        db.commit()


def test_health_endpoint():
    with TestClient(app) as client:
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"ok": True}


def test_news_sentiment_prediction_flow():
    _reset_db()
    with TestClient(app) as client:
        create = client.post(
            "/api/news/mock/NVDA",
            params={
                "headline": "NVIDIA earnings beat expectations",
                "summary": "Strong AI revenue growth outlook",
            },
        )
        assert create.status_code == 200
        created_payload = create.json()
        assert created_payload["ok"] is True

        news = client.get("/api/news/NVDA", params={"include_mock": "true"})
        assert news.status_code == 200
        news_rows = news.json()
        assert len(news_rows) >= 1
        assert any("NVIDIA" in row["headline"] for row in news_rows)

        sentiment = client.get("/api/news/NVDA/sentiment", params={"include_mock": "true"})
        assert sentiment.status_code == 200
        sentiment_payload = sentiment.json()
        assert sentiment_payload["ticker"] == "NVDA"
        assert sentiment_payload["count"] >= 1

        predict = client.post("/api/predict/NVDA/sync", json={"horizon_days": 5})
        assert predict.status_code == 200
        prediction = predict.json()
        assert prediction["ticker"] == "NVDA"
        assert prediction["recommendation"] in {"RISE", "STABLE", "FALL"}
        assert isinstance(prediction["feature_importances"], dict)
        assert "ewma_sentiment_1d" in prediction["feature_importances"]


def test_subscribe_endpoint_with_backfill_window():
    _reset_db()
    with TestClient(app) as client:
        response = client.post("/api/news/subscribe/NVDA", params={"backfill_days": 30, "backfill_limit": 50})
        assert response.status_code == 200
        payload = response.json()
        assert payload["ok"] is True
        assert payload["ticker"] == "NVDA"
        assert "NVDA" in payload["subscribed_tickers"]
        assert payload["backfill_days"] == 30
        assert payload["status"] == "backfill_queued"


def test_price_risk_endpoint_shape():
    with TestClient(app) as client:
        response = client.get("/api/price/NVDA/risk", params={"benchmark": "SPY", "days": 365})
        assert response.status_code == 200
        payload = response.json()
        assert "annualized_volatility" in payload
        assert "beta_to_benchmark" in payload
        assert "max_drawdown" in payload
        assert "high_water_mark" in payload


def test_source_breakdown_endpoint():
    _reset_db()
    with TestClient(app) as client:
        client.post(
            "/api/news/mock/NVDA",
            params={"headline": "NVIDIA beats expectations", "summary": "Strong GPU demand"},
        )
        response = client.get("/api/news/NVDA/sources", params={"include_mock": "true"})
        assert response.status_code == 200
        payload = response.json()
        assert isinstance(payload, list)
        assert payload[0]["source"] == "mock"
