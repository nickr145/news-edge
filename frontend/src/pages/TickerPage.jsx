import { useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import NewsFeed from '../components/NewsFeed'
import PredictionCard from '../components/PredictionCard'
import PriceChart from '../components/PriceChart'
import RiskPanel from '../components/RiskPanel'
import SentimentPanel from '../components/SentimentPanel'
import VerdictStrip from '../components/VerdictStrip'
import { TICKERS } from '../data/tickers'
import { useWatchlist } from '../hooks/useWatchlist'
import { api } from '../lib/api'
import { quoteFromBars } from '../lib/format'

export default function TickerPage() {
  const { symbol } = useParams()
  const ticker = useMemo(() => String(symbol || '').toUpperCase(), [symbol])
  const { isWatched, toggle } = useWatchlist()

  const [articles, setArticles] = useState([])
  const [summary, setSummary] = useState(null)
  const [trend, setTrend] = useState(null)
  const [bars, setBars] = useState([])
  const [prediction, setPrediction] = useState(null)
  const [risk, setRisk] = useState(null)
  const [windowDays, setWindowDays] = useState(30)
  const [minRelevance, setMinRelevance] = useState(0.35)
  const [horizonDays, setHorizonDays] = useState(5)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [predicting, setPredicting] = useState(false)

  const dedupeArticles = (items) => {
    const seen = new Set()
    const out = []
    for (const item of items) {
      const key = `${item.url || ''}|${item.headline || ''}|${item.published_at || ''}`
      if (seen.has(key)) continue
      seen.add(key)
      out.push(item)
    }
    return out
  }

  // Each panel fills in as its own request finishes: price and risk take a second, news analysis can take
  // several on a ticker's first visit, and the chart shouldn't wait for it. `token` drops late replies for a
  // ticker we've since left.
  const loadToken = useRef(0)
  const load = async (token) => {
    const trendHours = Math.min(windowDays * 24, 24 * 30)
    const barLimit = Math.max(windowDays, 30)
    const news = { days: windowDays, min_relevance: minRelevance, include_mock: false }
    const fill = (request, apply) => request
      .then((res) => { if (token === loadToken.current) apply(res.data); return true })
      .catch(() => false)
    const ok = await Promise.all([
      fill(api.get(`/api/price/${ticker}/bars`, { params: { limit: barLimit } }), (d) => setBars(d || [])),
      fill(api.get(`/api/price/${ticker}/risk`, { params: { benchmark: 'SPY', days: 365 } }), setRisk),
      fill(api.get(`/api/news/${ticker}`, { params: { ...news, limit: 100 } }), (d) => setArticles(dedupeArticles(d))),
      fill(api.get(`/api/news/${ticker}/sentiment`, { params: news }), setSummary),
      fill(api.get(`/api/news/${ticker}/trend`, { params: { ...news, hours: trendHours } }), setTrend),
    ])
    if (token === loadToken.current) setError(ok.every(Boolean) ? null : 'Failed to load data. Retrying…')
  }

  // A different ticker starts from a clean page, so one stock's price never sits beside another's news.
  useEffect(() => {
    setBars([]); setRisk(null); setArticles([]); setSummary(null); setTrend(null)
  }, [ticker])

  useEffect(() => {
    if (!ticker) return
    const token = ++loadToken.current
    setLoading(true)
    setError(null)
    api.post(`/api/news/subscribe/${ticker}`, null, {
      params: { backfill_days: windowDays, web_backfill: true }
    }).catch(() => {})
    load(token).finally(() => { if (token === loadToken.current) setLoading(false) })

    const id = setInterval(() => {
      if (!document.hidden) load(token)
    }, 30000)
    return () => { clearInterval(id); loadToken.current++ }
  }, [ticker, windowDays, minRelevance])

  const predictionRequest = useRef(0) // only the latest request may update the card (ticker switches, double clicks)
  const triggerPrediction = async () => {
    const id = ++predictionRequest.current
    setPredicting(true)
    try {
      const queued = await api.post(`/api/predict/${ticker}/sync`, { horizon_days: horizonDays })
      if (id !== predictionRequest.current) return
      setPrediction({ ...queued.data, horizonDays }) // remember what was asked, the dropdown may change later
      setError(null)
    } catch {
      if (id === predictionRequest.current) setError('Prediction failed. Please try again.')
    } finally {
      if (id === predictionRequest.current) setPredicting(false)
    }
  }

  // Show the default recommendation as soon as a ticker opens (and drop the previous ticker's).
  useEffect(() => {
    if (!ticker) return
    setPrediction(null)
    triggerPrediction()
  }, [ticker])

  const quote = useMemo(() => quoteFromBars(bars), [bars])
  const companyName = TICKERS.find((t) => t.symbol === ticker)?.name

  const watched = isWatched(ticker)

  return (
    <div className="ticker-page">
      <VerdictStrip
        ticker={ticker}
        companyName={companyName}
        quote={quote}
        prediction={prediction}
        predicting={predicting}
      />

      <div className="toolbar">
        <button className="btn" aria-pressed={watched} onClick={() => toggle(ticker)}>
          {watched ? '★ Watching' : '☆ Watch'}
        </button>
        <div className="toolbar-group">
          <label className="field">
            Window
            <select className="select" value={windowDays} onChange={(e) => setWindowDays(Number(e.target.value))}>
              <option value={1}>1 day</option>
              <option value={7}>7 days</option>
              <option value={30}>30 days</option>
              <option value={90}>90 days</option>
            </select>
          </label>
          <label className="field">
            Min relevance
            <select className="select" value={minRelevance} onChange={(e) => setMinRelevance(Number(e.target.value))}>
              <option value={0.2}>0.20</option>
              <option value={0.35}>0.35</option>
              <option value={0.5}>0.50</option>
              <option value={0.7}>0.70</option>
            </select>
          </label>
          <span className="live" title="News and prices refresh every 30 seconds"><span className="live-dot" />Live</span>
        </div>
      </div>

      {error && <div className="error-banner" role="alert">{error}</div>}
      {loading && <div className="loading-bar" role="progressbar" aria-label="Loading" />}

      <div className="ticker-layout">
        {/* The sticky rail can only stick inside this grid, so it scrolls away before the news section starts. */}
        <div className="ticker-analytics">
          <aside className="ticker-rail">
            <PredictionCard
              prediction={prediction}
              onPredict={triggerPrediction}
              predicting={predicting}
              horizonDays={horizonDays}
              onHorizonChange={setHorizonDays}
            />
            <RiskPanel risk={risk} />
          </aside>
          <div className="ticker-main">
            <PriceChart bars={bars} trend={trend} loading={loading} />
            <SentimentPanel summary={summary} trend={trend} />
          </div>
        </div>
        <div className="ticker-news">
          <NewsFeed articles={articles} loading={loading} />
        </div>
      </div>
    </div>
  )
}
