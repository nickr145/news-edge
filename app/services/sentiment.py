from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache


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

    def score_many(self, texts: list[tuple[str, str | None]]) -> list[SentimentResult]:
        return [self.score(h, s) for h, s in texts]


class VaderEngine(BaseSentimentEngine):
    model_name = "vader"
    positive_words = {"beat", "surge", "bullish", "growth", "strong", "upgrade", "outperform", "profit", "record"}
    negative_words = {"miss", "drop", "bearish", "decline", "weak", "downgrade", "underperform", "loss", "lawsuit"}

    def __init__(self) -> None:
        self._analyzer = None
        try:
            from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

            self._analyzer = SentimentIntensityAnalyzer()
        except Exception:
            self._analyzer = None

    def score(self, headline: str, summary: str | None = None) -> SentimentResult:
        text = f"{headline}. {summary or ''}".strip()
        if self._analyzer:
            score = self._analyzer.polarity_scores(text)
            compound = float(score.get("compound", 0.0))
        else:
            t = text.lower()
            pos = sum(word in t for word in self.positive_words)
            neg = sum(word in t for word in self.negative_words)
            total = max(pos + neg, 1)
            compound = max(min((pos - neg) / total, 1.0), -1.0)

        score_positive = max(0.0, compound)
        score_negative = max(0.0, -compound)
        score_neutral = max(0.0, 1.0 - abs(compound))

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
            compound=float(compound),
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
                truncation=True,
            )
        except Exception:
            self._pipeline = None

    @staticmethod
    def _to_result(scores: dict[str, float]) -> SentimentResult:
        score_positive = float(scores.get("positive", 0.0))
        score_negative = float(scores.get("negative", 0.0))
        score_neutral = float(scores.get("neutral", 0.0))
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
            model="finbert",
            score_positive=score_positive,
            score_negative=score_negative,
            score_neutral=score_neutral,
            compound=float(compound),
            label=label,
        )

    def score(self, headline: str, summary: str | None = None) -> SentimentResult:
        if self._pipeline is None:
            return VaderEngine().score(headline, summary)

        text = f"{headline}. {summary or ''}"[:512]
        result = self._pipeline(text)[0]
        scores = {row["label"].lower(): float(row["score"]) for row in result}
        return self._to_result(scores)

    def score_many(self, texts: list[tuple[str, str | None]]) -> list[SentimentResult]:
        if self._pipeline is None:
            fallback = VaderEngine()
            return [fallback.score(h, s) for h, s in texts]

        payload = [f"{h}. {s or ''}"[:512] for h, s in texts]
        outputs = self._pipeline(payload, batch_size=min(32, max(1, len(payload))))
        results: list[SentimentResult] = []
        for output in outputs:
            scores = {row["label"].lower(): float(row["score"]) for row in output}
            results.append(self._to_result(scores))
        return results


@lru_cache(maxsize=4)
def get_sentiment_engine(model_name: str) -> BaseSentimentEngine:
    model_name = (model_name or "vader").lower()
    if model_name == "finbert":
        return FinbertEngine()
    return VaderEngine()
