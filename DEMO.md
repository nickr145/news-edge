# NewsEdge demo script (~5 min)

**Setup:** web at https://news-edge-ai.vercel.app in a browser, iOS app in the simulator beside it. Pre-add 3–4 tickers to the watchlist (e.g. AAPL, TSLA, AMZN, BAC) so both home screens look populated.

## 0:00 Pitch (20s)
"NewsEdge turns the stock news firehose into a sentiment signal. News comes in live, gets scored by a financial-domain NLP model, and feeds a price-direction prediction. A React web app and a native iOS app, neither needing a server of its own."

## 0:20 Web home (40s)
- Show the watchlist cards: ticker, 7-day EWMA sentiment, article count.
- Type `bank america` in search → autocomplete resolves to BAC. Mention it matches company names, not just symbols, and supports keyboard navigation.

## 1:00 Ticker page (90s)
- Open AAPL. Say: "On first open the app backfills history from Google News, then accrues news in the browser. Web scores headlines with VADER; the iOS app uses FinBERT on device."
- **Price & sentiment overlay:** close price and daily sentiment on one time axis.
- Flip the history window (1/7/30/90d) and min-relevance (0.20→0.70). "Relevance filtering drops weak cross-market articles, so the feed is mostly on-topic."
- **News feed:** one row per event ("+N outlets" badge), refreshed every 30 seconds.
- **Risk panel:** volatility, beta vs SPY, max drawdown, cumulative return.

## 2:30 Prediction (60s)
- Run a prediction; switch horizon 1 / 5 / 14 days.
- Output is `RISE` / `STABLE` / `FALL`, a direction signal rather than trading advice.
- Be upfront: there is no trained model. The signal is a rule on recency-weighted sentiment over the chosen horizon (RISE above +0.15, FALL below -0.15), and the card lists the input feature values (sentiment, RSI, momentum, Bollinger position, volume ratio) rather than SHAP contributions.

## 3:30 iOS (75s)
- Switch to the simulator. Same watchlist as native card tiles.
- Swipe a card left → red remove button. Tap a card → detail screen.
- Detail screen mirrors the web: stats, mini price/sentiment charts, risk, prediction, news feed.
- Call out that the iOS app has no backend: it pulls Yahoo Finance directly and scores sentiment on device, like Apple Stocks.
- Mention the home-screen widget showing 7-day EWMA per watchlisted ticker.

## 4:45 Architecture + wrap (45s)
"No server of our own. Yahoo Finance, Nasdaq and Google News feed both clients; the web app reaches them through one tiny allow-listed Vercel function, the iOS app calls them directly. Sentiment, relevance, event grouping, risk and the signal are all computed on the device or in the browser. Web is on Vercel; the iOS app and widget are on-device."

## Before you go live
- [ ] Open each demo ticker once so the first-open news backfill is done (web stores it per browser, so use the same browser).
- [ ] Simulator already on the watchlist screen.
- [ ] Have a fallback: if a ticker's feed is quiet, switch to a busier one (AAPL, TSLA, NVDA).
