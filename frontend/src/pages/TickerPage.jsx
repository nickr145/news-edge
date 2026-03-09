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

  const load = async () => {
    const trendHours = Math.min(windowDays * 24, 24 * 30)
    const [newsRes, summaryRes, trendRes, riskRes] = await Promise.all([
      api.get(`/api/news/${ticker}`, { params: { days: windowDays, limit: 100, min_relevance: minRelevance } }),
      api.get(`/api/news/${ticker}/sentiment`, { params: { days: windowDays, min_relevance: minRelevance } }),
      api.get(`/api/news/${ticker}/trend`, { params: { hours: trendHours, min_relevance: minRelevance } }),
      api.get(`/api/price/${ticker}/risk`, { params: { benchmark: 'SPY', days: 365 } })
    ])
    setArticles(newsRes.data)
    setSummary(summaryRes.data)
    setTrend(trendRes.data)
    setRisk(riskRes.data)
  }

  useEffect(() => {
    if (!ticker) return
    api.post(`/api/news/subscribe/${ticker}`, null, { params: { backfill_days: windowDays } }).catch(() => {})
    load()
    const id = setInterval(() => {
      load()
    }, 8000)
    return () => clearInterval(id)
  }, [ticker, windowDays, minRelevance])

  useEffect(() => {
    if (!ticker) return
    const ws = new WebSocket(newsSocketUrl(ticker))
    ws.onmessage = (evt) => {
      const article = JSON.parse(evt.data)
      setArticles((prev) => [article, ...prev].slice(0, 100))
      const trendHours = Math.min(windowDays * 24, 24 * 30)
      api.get(`/api/news/${ticker}/sentiment`, { params: { days: windowDays, min_relevance: minRelevance } }).then((r) => setSummary(r.data)).catch(() => {})
      api.get(`/api/news/${ticker}/trend`, { params: { hours: trendHours, min_relevance: minRelevance } }).then((r) => setTrend(r.data)).catch(() => {})
    }
    return () => ws.close()
  }, [ticker, windowDays, minRelevance])

  const triggerPrediction = async () => {
    const queued = await api.post(`/api/predict/${ticker}/sync`, { horizon_days: 5 })
    setPrediction(queued.data)
  }

  return (
    <div className="dashboard-grid">
      <section className="card">
        <h2>{ticker}</h2>
        <p>Real-time news, sentiment trend, and recommendation output.</p>
        <div className="row">
          <label htmlFor="windowDays">History Window</label>
          <select id="windowDays" value={windowDays} onChange={(e) => setWindowDays(Number(e.target.value))}>
            <option value={1}>1 day</option>
            <option value={7}>7 days</option>
            <option value={30}>30 days</option>
            <option value={90}>90 days</option>
          </select>
        </div>
        <div className="row">
          <label htmlFor="relevance">Min Relevance</label>
          <select id="relevance" value={minRelevance} onChange={(e) => setMinRelevance(Number(e.target.value))}>
            <option value={0.2}>0.20 (Broader)</option>
            <option value={0.35}>0.35 (Default)</option>
            <option value={0.5}>0.50 (Stricter)</option>
            <option value={0.7}>0.70 (Very strict)</option>
          </select>
        </div>
      </section>
      <PredictionCard prediction={prediction} onPredict={triggerPrediction} />
      <RiskPanel risk={risk} />
      <SentimentPanel summary={summary} trend={trend} />
      <NewsFeed articles={articles} />
    </div>
  )
}
