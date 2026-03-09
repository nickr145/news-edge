from __future__ import annotations

from app.db.session import SessionLocal
from app.ml.dataset import build_training_dataset
from app.ml.model import FEATURE_COLUMNS, train_model


def main(ticker: str = "NVDA") -> None:
    with SessionLocal() as db:
        df = build_training_dataset(db, ticker=ticker)
        if df.empty:
            print("No dataset rows available. Ingest more news and ensure Alpaca bars are configured.")
            return

        train_df = df[[*FEATURE_COLUMNS, "target"]].copy().dropna()
        bundle = train_model(train_df)
        print(f"Trained model classes={list(bundle.encoder.classes_)} rows={len(train_df)}")


if __name__ == "__main__":
    main()
