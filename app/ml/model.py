from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
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
    metadata: dict


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


def _expected_calibration_error(y_true: np.ndarray, probs: np.ndarray, bins: int = 10) -> float:
    confidences = probs.max(axis=1)
    predictions = probs.argmax(axis=1)
    correctness = (predictions == y_true).astype(float)
    edges = np.linspace(0.0, 1.0, bins + 1)
    ece = 0.0
    for i in range(bins):
        lo, hi = edges[i], edges[i + 1]
        mask = (confidences > lo) & (confidences <= hi)
        if not np.any(mask):
            continue
        bucket_conf = float(np.mean(confidences[mask]))
        bucket_acc = float(np.mean(correctness[mask]))
        ece += abs(bucket_acc - bucket_conf) * (np.sum(mask) / len(confidences))
    return float(ece)


def train_model(df):
    try:
        import xgboost as xgb
    except Exception:
        return None

    X = df[FEATURE_COLUMNS]
    y_raw = df["target"].astype(str)

    encoder = SimpleLabelEncoder()
    y = encoder.fit_transform(y_raw)

    if len(df) >= 50:
        split_idx = int(len(df) * 0.8)
        X_train = X.iloc[:split_idx]
        y_train = y[:split_idx]
        X_val = X.iloc[split_idx:]
        y_val = y[split_idx:]
    else:
        X_train, y_train = X, y
        X_val, y_val = X, y

    model = xgb.XGBClassifier(
        n_estimators=150,
        max_depth=4,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        objective="multi:softprob",
        eval_metric="mlogloss",
    )
    model.fit(X_train, y_train)

    val_probs = model.predict_proba(X_val)
    val_preds = val_probs.argmax(axis=1)
    accuracy = float(np.mean(val_preds == y_val)) if len(y_val) else 0.0
    brier = float(np.mean((np.eye(len(encoder.classes_))[y_val] - val_probs) ** 2)) if len(y_val) else 0.0
    ece = _expected_calibration_error(y_val, val_probs) if len(y_val) else 0.0

    metadata = {
        "trained_at": datetime.now(timezone.utc).isoformat(),
        "rows_total": int(len(df)),
        "rows_train": int(len(X_train)),
        "rows_val": int(len(X_val)),
        "classes": list(encoder.classes_),
        "metrics": {
            "val_accuracy": round(accuracy, 4),
            "val_brier": round(brier, 6),
            "val_ece": round(ece, 6),
        },
        "version": "xgb_v2",
    }

    bundle = ModelBundle(model=model, encoder=encoder, metadata=metadata)
    save_bundle(bundle)
    return bundle


def predict_proba_row(bundle: ModelBundle, row: dict[str, float]) -> dict[str, float]:
    if not hasattr(bundle.model, "predict_proba"):
        return {"RISE": 0.33, "STABLE": 0.34, "FALL": 0.33}

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
