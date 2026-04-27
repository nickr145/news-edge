import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import NewsFeed from '../components/NewsFeed'
import PredictionCard from '../components/PredictionCard'
import RiskPanel from '../components/RiskPanel'
import SentimentPanel from '../components/SentimentPanel'
import { api, newsSocketUrl } from '../lib/api'

export default function TickerPage() {
  const { symbol } = useParams()
  const ticker = useMemo(() => String(symbol || '').toUpperCase(), [symbol])

  const [articles, setArticles] = useState([])
  const [summary, setSummary] = useState(null)
  const [trend, setTrend] = useState(null)
  const [prediction, setPrediction] = useState(null)
  const [risk, setRisk] = useState(null)
  const [windowDays, setWindowDays] = useState(30)
  const [minRelevance, setMinRelevance] = useState(0.35)
  const [loading, setLoading] = useState(false)
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

  const load = async () => {
    const trendHours = Math.min(windowDays * 24, 24 * 30)
    try {
      const [newsRes, summaryRes, trendRes, riskRes] = await Promise.all([
        api.get(`/api/news/${ticker}`, { params: { days: windowDays, limit: 100, min_relevance: minRelevance, include_mock: false } }),
        api.get(`/api/news/${ticker}/sentiment`, { params: { days: windowDays, min_relevance: minRelevance, include_mock: false } }),
        api.get(`/api/news/${ticker}/trend`, { params: { hours: trendHours, min_relevance: minRelevance, include_mock: false } }),
        api.get(`/api/price/${ticker}/risk`, { params: { benchmark: 'SPY', days: 365 } })
      ])
      setArticles(dedupeArticles(newsRes.data))
      setSummary(summaryRes.data)
      setTrend(trendRes.data)
      setRisk(riskRes.data)
      setError(null)
    } catch {
      setError('Failed to load data. Retrying…')
    }
  }

  useEffect(() => {
    if (!ticker) return
    setLoading(true)
    setError(null)
    api.post(`/api/news/subscribe/${ticker}`, null, {
      params: { backfill_days: windowDays, web_backfill: true }
    }).catch(() => {})
    load().finally(() => setLoading(false))

    // Poll at 30s — the WebSocket handles live article delivery;
    // polling just keeps sentiment/risk/trend fresh.
    // Pause when the tab is hidden so we don't burn requests in the background.
    const id = setInterval(() => {
      if (!document.hidden) load()
    }, 30000)
    return () => clearInterval(id)
  }, [ticker, windowDays, minRelevance])

  useEffect(() => {
    if (!ticker) return
    const ws = new WebSocket(newsSocketUrl(ticker))
    ws.onmessage = (evt) => {
      const article = JSON.parse(evt.data)
      setArticles((prev) => dedupeArticles([article, ...prev]).slice(0, 100))
      const trendHours = Math.min(windowDays * 24, 24 * 30)
      api.get(`/api/news/${ticker}/sentiment`, { params: { days: windowDays, min_relevance: minRelevance, include_mock: false } }).then((r) => setSummary(r.data)).catch(() => {})
      api.get(`/api/news/${ticker}/trend`, { params: { hours: trendHours, min_relevance: minRelevance, include_mock: false } }).then((r) => setTrend(r.data)).catch(() => {})
    }
    ws.onerror = () => {}
    return () => ws.close()
  }, [ticker, windowDays, minRelevance])

  const triggerPrediction = async () => {
    if (predicting) return
    setPredicting(true)
    try {
      const queued = await api.post(`/api/predict/${ticker}/sync`, { horizon_days: 5 })
      setPrediction(queued.data)
      setError(null)
    } catch {
      setError('Prediction failed. Please try again.')
    } finally {
      setPredicting(false)
    }
  }

  return (
    <div className="ticker-page">
      <div className="ticker-header">
        <div>
          <div className="ticker-symbol">{ticker}</div>
          <div className="ticker-tagline">Sentiment intelligence · Live feed</div>
        </div>
        <div className="ticker-controls">
          <span className="ctrl-label">Window</span>
          <select className="ctrl-select" value={windowDays} onChange={(e) => setWindowDays(Number(e.target.value))}>
            <option value={1}>1 day</option>
            <option value={7}>7 days</option>
            <option value={30}>30 days</option>
            <option value={90}>90 days</option>
          </select>
          <span className="ctrl-label">Relevance</span>
          <select className="ctrl-select" value={minRelevance} onChange={(e) => setMinRelevance(Number(e.target.value))}>
            <option value={0.2}>0.20</option>
            <option value={0.35}>0.35</option>
            <option value={0.5}>0.50</option>
            <option value={0.7}>0.70</option>
          </select>
          <span className="live-indicator">
            <span className="live-dot" />
            LIVE
          </span>
        </div>
      </div>

      {error && <div className="error-banner">{error}</div>}
      {loading && <div className="loading-bar" />}

      <div className="ticker-layout">
        <aside className="ticker-sidebar">
          <PredictionCard prediction={prediction} onPredict={triggerPrediction} predicting={predicting} />
          <RiskPanel risk={risk} />
        </aside>
        <div className="ticker-main">
          <SentimentPanel summary={summary} trend={trend} />
          <NewsFeed articles={articles} loading={loading} />
        </div>
      </div>
    </div>
  )
}
