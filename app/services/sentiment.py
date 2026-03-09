from __future__ import annotations

from dataclasses import dataclass


@dataclass
class SentimentResult:
    model: str
    score_positive: float
    score_negative: float
    score_neutral: float
    compound: float
    label: str


class BaseSentimentEngine:
    model_name = "base"

    def score(self, headline: str, summary: str | None = None) -> SentimentResult:
        raise NotImplementedError


class VaderLikeEngine(BaseSentimentEngine):
    model_name = "vader"

    positive_words = {
        "beat",
        "surge",
        "bullish",
        "growth",
        "strong",
        "upgrade",
        "outperform",
        "profit",
        "record",
    }
    negative_words = {
        "miss",
        "drop",
        "bearish",
        "decline",
        "weak",
        "downgrade",
        "underperform",
        "loss",
        "lawsuit",
    }

    def score(self, headline: str, summary: str | None = None) -> SentimentResult:
        text = f"{headline} {summary or ''}".lower()
        pos = sum(word in text for word in self.positive_words)
        neg = sum(word in text for word in self.negative_words)
        total = max(pos + neg, 1)

        score_positive = pos / total
        score_negative = neg / total
        score_neutral = 1.0 - min(score_positive + score_negative, 1.0)
        compound = max(min(score_positive - score_negative, 1.0), -1.0)

        if compound > 0.05:
            label = "POSITIVE"
        elif compound < -0.05:
            label = "NEGATIVE"
        else:
            label = "NEUTRAL"

        return SentimentResult(
            model=self.model_name,
            score_positive=score_positive,
            score_negative=score_negative,
            score_neutral=score_neutral,
            compound=compound,
            label=label,
        )


class FinbertEngine(BaseSentimentEngine):
    model_name = "finbert"

    def __init__(self) -> None:
        self._pipeline = None
        try:
            from transformers import pipeline

            self._pipeline = pipeline(
                "text-classification",
                model="ProsusAI/finbert",
                return_all_scores=True,
            )
        except Exception:
            self._pipeline = None

    def score(self, headline: str, summary: str | None = None) -> SentimentResult:
        if self._pipeline is None:
            return VaderLikeEngine().score(headline, summary)

        text = f"{headline}. {summary or ''}"[:512]
        result = self._pipeline(text)[0]
        scores = {row["label"].lower(): float(row["score"]) for row in result}

        score_positive = scores.get("positive", 0.0)
        score_negative = scores.get("negative", 0.0)
        score_neutral = scores.get("neutral", 0.0)
        compound = max(min(score_positive - score_negative, 1.0), -1.0)

        label = max(
            {
                "POSITIVE": score_positive,
                "NEGATIVE": score_negative,
                "NEUTRAL": score_neutral,
            },
            key=lambda k: {
                "POSITIVE": score_positive,
                "NEGATIVE": score_negative,
                "NEUTRAL": score_neutral,
            }[k],
        )

        return SentimentResult(
            model=self.model_name,
            score_positive=score_positive,
            score_negative=score_negative,
            score_neutral=score_neutral,
            compound=compound,
            label=label,
        )


def get_sentiment_engine(model_name: str) -> BaseSentimentEngine:
    model_name = (model_name or "vader").lower()
    if model_name == "finbert":
        return FinbertEngine()
    return VaderLikeEngine()
