from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import joblib
import numpy as np

from app.core.config import get_settings


FEATURE_COLUMNS = [
    "ewma_sentiment_1d",
    "ewma_sentiment_7d",
    "sentiment_volatility",
    "article_volume_24h",
    "rsi_14",
    "momentum_5d",
    "bb_position",
    "volume_ratio",
]


class SimpleLabelEncoder:
    def __init__(self) -> None:
        self.classes_: list[str] = []
        self._class_to_idx: dict[str, int] = {}

    def fit_transform(self, labels) -> np.ndarray:
        self.classes_ = sorted({str(v) for v in labels})
        self._class_to_idx = {label: idx for idx, label in enumerate(self.classes_)}
        return np.array([self._class_to_idx[str(v)] for v in labels], dtype=int)

    def transform(self, labels) -> np.ndarray:
        return np.array([self._class_to_idx[str(v)] for v in labels], dtype=int)

    def inverse_transform(self, indices) -> np.ndarray:
        return np.array([self.classes_[int(i)] for i in indices], dtype=object)


@dataclass
class ModelBundle:
    model: object
    encoder: SimpleLabelEncoder


def save_bundle(bundle: ModelBundle) -> None:
    path = Path(get_settings().model_artifact_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, path)


def load_bundle() -> ModelBundle | None:
    path = Path(get_settings().model_artifact_path)
    if not path.exists():
        return None
    try:
        return joblib.load(path)
    except Exception:
        return None


def train_model(df):
    try:
        import xgboost as xgb
    except Exception:
        return None

    X = df[FEATURE_COLUMNS]
    y_raw = df["target"].astype(str)

    encoder = SimpleLabelEncoder()
    y = encoder.fit_transform(y_raw)

    model = xgb.XGBClassifier(
        n_estimators=150,
        max_depth=4,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        objective="multi:softprob",
        eval_metric="mlogloss",
    )
    model.fit(X, y)
    bundle = ModelBundle(model=model, encoder=encoder)
    save_bundle(bundle)
    return bundle


def predict_proba_row(bundle: ModelBundle, row: dict[str, float]) -> dict[str, float]:
    if not hasattr(bundle.model, "predict_proba"):
        return {"BUY": 0.33, "HOLD": 0.34, "SELL": 0.33}

    x = np.array([[row[c] for c in FEATURE_COLUMNS]], dtype=float)
    probs = bundle.model.predict_proba(x)[0]
    labels = bundle.encoder.inverse_transform(np.arange(len(probs)))
    return {label: float(prob) for label, prob in zip(labels, probs, strict=False)}


def explain_row(bundle: ModelBundle, row: dict[str, float], predicted_label: str) -> dict[str, float]:
    """Return SHAP attributions for the predicted class.

    Falls back to raw feature values when SHAP is unavailable.
    """
    x = np.array([[row[c] for c in FEATURE_COLUMNS]], dtype=float)
    try:
        import shap
    except Exception:
        return {k: float(v) for k, v in row.items()}

    try:
        explainer = shap.TreeExplainer(bundle.model)
        shap_values = explainer.shap_values(x)
        class_index = int(bundle.encoder.transform([predicted_label])[0])
    except Exception:
        return {k: float(v) for k, v in row.items()}

    if isinstance(shap_values, list):
        selected = np.asarray(shap_values[class_index])[0]
    else:
        arr = np.asarray(shap_values)
        if arr.ndim == 3:
            selected = arr[0, :, class_index]
        elif arr.ndim == 2:
            selected = arr[0]
        else:
            selected = np.zeros(len(FEATURE_COLUMNS))

    return {feature: float(value) for feature, value in zip(FEATURE_COLUMNS, selected, strict=False)}
