---
name: improvement1 branch fixes
description: Bugs fixed and improvements made on the improvement1 branch
type: project
---

Three backend bugs fixed and several frontend UX improvements made on the improvement1 branch.

**Backend bugs:**
- `routes_news.py`: `GET /subscriptions` was registered after `GET /{ticker}`, making it unreachable (FastAPI matched the dynamic route first). Fixed by moving `/subscriptions` before `/{ticker}`.
- `web_backfill.py`: `_find_existing_by_signature` ran a 5,000-row DB query per article being inserted (O(n²)). Replaced with a single bulk query building a set upfront, plus a batched URL existence check.
- `dataset.py`: `ewma_sentiment_1d` was just the last intraday value (not EWMA); `ewma_sentiment_7d` was a within-day mean (not 7-day rolling). Both caused train/serve feature skew vs. inference-time `get_sentiment_summary`. Fixed to use `compute_ewma(scores)` for 1d and `pandas ewm(span=7)` of daily means for 7d.

**Frontend improvements:**
- `RiskPanel.jsx`: Added `cumulative_return` metric (was available from API but never shown).
- `PredictionCard.jsx`: Added `sentiment_score` and `horizon_days` display; added disabled/loading state to the Run Prediction button.
- `SentimentPanel.jsx`: Unhid the X-axis (had `hide`); added angled date labels, zero reference line, styled tooltips, chart titles.
- `TickerPage.jsx`: Added `loading`, `error`, and `predicting` states; errors shown in red banner; initial load spinner.
- `styles.css`: Changed `metrics-row` to `auto-fit minmax(80px, 1fr)` to handle 4 or 5 columns; added `.positive`/`.negative` color classes, `.error-banner`, `.loading-text`, `.chart-label`, `button:disabled`.

**Why:** fix correctness and usability for the initial feature-complete state of the platform.
