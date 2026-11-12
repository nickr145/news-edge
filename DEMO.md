# NewsEdge demo script (~5 min)

**Setup:** web at https://news-edge-ai.vercel.app in a browser, iOS app in the simulator beside it. Pre-add 3–4 tickers to the watchlist (e.g. AAPL, TSLA, AMZN, BAC) so both home screens look populated.

## 0:00 Pitch (20s)
"NewsEdge turns the stock news firehose into a sentiment signal. News comes in live, gets scored by a financial-domain NLP model, and feeds a price-direction prediction. One backend serves a React web app and a native iOS app."

## 0:20 Web home (40s)
- Show the watchlist cards: ticker, 7-day EWMA sentiment, article count.
- Type `bank america` in search → autocomplete resolves to BAC. Mention it matches company names, not just symbols, and supports keyboard navigation.

## 1:00 Ticker page (90s)
- Open AAPL. Say: "On first open the app subscribes the ticker, backfills history from Alpaca, and scores every article with FinBERT. VADER is the fallback."
- **Price & sentiment overlay:** close price and daily sentiment on one time axis.
- Flip the history window (1/7/30/90d) and min-relevance (0.20→0.70). "Relevance filtering drops weak cross-market articles, so the feed is mostly on-topic."
- **Live feed:** articles arrive over a WebSocket (`/ws/news/{ticker}`).
- **Risk panel:** volatility, beta vs SPY, max drawdown, cumulative return.

## 2:30 Prediction (60s)
- Run a prediction; switch horizon 1 / 5 / 14 days.
- Output is `RISE` / `STABLE` / `FALL`, a direction signal rather than trading advice.
- **SHAP bars:** top 5 features driving the call (sentiment, RSI, momentum, Bollinger position, volume ratio).
- Be upfront: if no trained model artifact exists (as on the current Railway deploy), it falls back to a rule on EWMA (±0.15). The weekly Celery job retrains XGBoost.

## 3:30 iOS (75s)
- Switch to the simulator. Same watchlist as native card tiles.
- Swipe a card left → red remove button. Tap a card → detail screen.
- Detail screen mirrors the web: stats, mini price/sentiment charts, risk, prediction, news feed.
- Call out that the iOS app has no backend: it pulls Yahoo Finance directly and scores sentiment on device, like Apple Stocks.
- Mention the home-screen widget showing 7-day EWMA per watchlisted ticker.

## 4:45 Architecture + wrap (45s)
"Alpaca WebSocket → Redis Streams → Celery workers → FinBERT → Postgres. FastAPI serves both clients. Celery Beat refreshes price labels daily and retrains XGBoost weekly. Deployed on Railway (API) and Vercel (web). Backend tests are green."

## Before you go live
- [ ] Hit `/health` on the Railway backend so the *web* demo isn't cold (the iOS app no longer uses it).
- [ ] Open each demo ticker once so backfill is done.
- [ ] Simulator already on the watchlist screen.
- [ ] Have a fallback: if the live feed is quiet, `POST /api/news/mock/{ticker}` pushes a test article.
