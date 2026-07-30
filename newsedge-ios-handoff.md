# NewsEdge iOS Port — Handoff Brief for Claude Code

## Goal
Build a native iOS app (Swift + SwiftUI, Xcode 26) that replicates the existing NewsEdge React web frontend. The FastAPI backend stays completely untouched — the iOS app is a new client for the same API.

## Environment (already set up)
- Mac: M3 Pro, macOS Tahoe 26.6, Xcode 26.6 (working — a stale CoreDevice framework issue was already fixed)
- Repo: local working copy of `github.com/nickr145/news-edge` (monorepo)
- Decision made: iOS app lives **inside this repo** at `ios/` alongside `app/` (FastAPI) and `frontend/` (React). Do NOT create a nested git repo.

## Repo layout (relevant parts)
```
news-edge/
├── app/                  # FastAPI backend — DO NOT MODIFY
│   ├── api/              # routes_news.py, routes_prediction.py, routes_price.py,
│   │                     # routes_fundamentals.py, routes_health.py, routes_ws.py
│   └── schemas/          # news.py, prediction.py, fundamentals.py  ← source of truth for models
├── frontend/             # React + Vite web app — reference implementation, DO NOT MODIFY
│   └── src/
│       ├── components/   # NewsFeed, PriceChart, SentimentPanel, PredictionCard,
│       │                 # RiskPanel, WatchlistPanel, TickerSearch
│       ├── pages/        # SearchPage.jsx, TickerPage.jsx
│       ├── hooks/useWatchlist.js   # watchlist in localStorage
│       ├── lib/api.js              # axios client ← source of truth for endpoints
│       └── data/tickers.js         # static ticker autocomplete data
└── ios/                  # ← CREATE THE XCODE PROJECT HERE (SwiftUI App template, no storage)
```

## Task order

### 1. Project scaffold
- Create `ios/NewsEdge` — iOS App template, SwiftUI, Swift, no Core Data/SwiftData.
- Add to root `.gitignore`: `ios/**/xcuserdata/`, `*.xcuserstate`, `DerivedData/`. Commit the `.xcodeproj` and (later) `Package.resolved`.

### 2. Data layer (do this first, verify against real files)
- Read `app/schemas/news.py`, `app/schemas/prediction.py`, `app/schemas/fundamentals.py` and generate matching Swift `Codable` structs. Backend uses snake_case JSON — use `.convertFromSnakeCase` (or explicit CodingKeys) and ISO8601 date decoding for `published_at` and similar fields.
- Read `frontend/src/lib/api.js` and build an `APIClient` (URLSession, async/await) covering every endpoint it calls, plus the WebSocket route in `app/api/routes_ws.py` (`/ws/news/{symbol}`) via `URLSessionWebSocketTask`.
- `APIConfig`: `#if DEBUG` → `http://localhost:8000` (simulator shares the Mac's network; add an ATS exception for local HTTP in the Debug config only), else the production API base URL (ask the user for it — likely the Vercel deployment).

### 3. State & storage
- `WatchlistStore` (`@Observable`): port `frontend/src/hooks/useWatchlist.js`, persist symbols in `UserDefaults`.
- Convert `frontend/src/data/tickers.js` to a bundled JSON resource for search/autocomplete.

### 4. Screens (mirror the React pages/components)
- Navigation: `NavigationStack`, two screens like the web app's two routes.
- **SearchScreen** (≈ SearchPage.jsx): searchable ticker list (`.searchable()`), watchlist section.
- **TickerScreen** (≈ TickerPage.jsx), composed of SwiftUI equivalents of:
  - PriceChart → **Swift Charts** (dual-axis price + sentiment overlay; match the web version's windows/horizon selectors using segmented `Picker`s)
  - SentimentPanel → Swift Charts (trend line, label distribution)
  - PredictionCard + RiskPanel → prediction output incl. SHAP-style feature bars (Swift Charts bar chart)
  - NewsFeed → `List` of articles, live-updating from the WebSocket stream
- Use Xcode Previews to visually verify each view as it's built.

### 5. Polish / later
- Loading & error states for every fetch; pull-to-refresh on the feed.
- Reconnect logic for the WebSocket.
- Stretch (not now): home-screen widget showing watchlist sentiment (EWMA).

## Ground rules
- Backend (`app/`) and web frontend (`frontend/`) are read-only reference — never edit them.
- The Pydantic schemas and `api.js` are the contract; if Swift models disagree with them, the Swift side is wrong.
- Match the web app's behavior first; adopt native iOS idioms (navigation, pickers, searchable) where they're clearly better.
- Target: recent iOS (26 SDK is installed). App Store submissions require the iOS 26 SDK as of April 2026, so build with it.

## Definition of done (phase 1)
Runs in the iOS simulator against the local backend (`uvicorn` on :8000): search a ticker, open its detail screen, see price/sentiment charts, prediction card, and live news feed; add/remove tickers from a persisted watchlist.
