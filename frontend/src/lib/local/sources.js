// Market-data sources, fetched through the allow-listed /api/proxy (browsers can't call them directly).
import { yahooSymbol } from './analytics'

const dayStr = (d) => d.toISOString().slice(0, 10)

export function createSources({ fetchImpl = (...a) => fetch(...a), proxyBase = '/api/proxy', storage } = {}) {
  const memo = new Map() // url -> { at, text }

  async function get(target, params, ttlMs) {
    const url = `${proxyBase}?${new URLSearchParams({ target, ...params })}`
    const hit = memo.get(url)
    if (hit && Date.now() - hit.at < ttlMs) return hit.text
    const res = await fetchImpl(url)
    if (!res.ok) {
      const err = new Error(`${target} ${res.status}`)
      err.status = res.status
      throw err
    }
    const text = await res.text()
    memo.set(url, { at: Date.now(), text })
    return text
  }

  async function yahooBars(symbol) {
    let text
    try { text = await get('chart', { symbol }, 300_000) } catch (e) { if (e.status === 404) return []; throw e } // 404 = unknown symbol
    const result = JSON.parse(text)?.chart?.result?.[0]
    const q = result?.indicators?.quote?.[0]
    if (!result || !q) return []
    const bars = []
    ;(result.timestamp || []).forEach((ts, i) => {
      const [o, h, l, c] = [q.open[i], q.high[i], q.low[i], q.close[i]]
      if ([o, h, l, c].some((x) => x == null)) return
      bars.push({ timestamp: new Date(ts * 1000).toISOString(), open: o, high: h, low: l, close: c, volume: q.volume[i] ?? 0 })
    })
    return bars
  }

  const money = (s) => Number(String(s).replace(/[$,]/g, ''))

  /** `{"data":{"tradesTable":{"rows":[{"date":"11/10/2026","close":"$348.51",...}]}}}`, newest first. */
  function parseNasdaq(text) {
    let rows
    try { rows = JSON.parse(text)?.data?.tradesTable?.rows } catch { return [] }
    if (!Array.isArray(rows)) return []
    return rows.flatMap((r) => {
      const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(r.date || '')
      const [o, h, l, c] = [r.open, r.high, r.low, r.close].map(money)
      if (!m || [o, h, l, c].some(Number.isNaN)) return []
      return [{ timestamp: new Date(Date.UTC(+m[3], +m[1] - 1, +m[2])).toISOString(), open: o, high: h, low: l, close: c, volume: money(r.volume) || 0 }]
    }).reverse()
  }

  async function nasdaqBars(symbol) {
    const now = new Date()
    for (const assetclass of ['stocks', 'etf']) {
      const bars = parseNasdaq(await get('nasdaq', { symbol, assetclass, fromdate: dayStr(new Date(now - 370 * 86_400_000)), todate: dayStr(now) }, 300_000))
      if (bars.length) return bars
    }
    return []
  }

  const cacheKey = (s) => `newsedge_bars_${s}`

  /** ~1y daily bars, oldest first: Yahoo -> Nasdaq -> last good bars in localStorage. [] for unknown symbols. */
  async function bars(ticker) {
    const symbol = yahooSymbol(ticker)
    let failure
    try {
      const b = await yahooBars(symbol)
      if (b.length) { save(symbol, b); return b }
    } catch (e) { failure = e }
    try {
      const b = await nasdaqBars(symbol)
      if (b.length) { save(symbol, b); return b }
    } catch { /* fall through */ }
    const cached = load(symbol)
    if (cached?.length) return cached
    if (failure) throw failure
    return []
  }

  const save = (symbol, b) => { try { storage?.setItem(cacheKey(symbol), JSON.stringify(b)) } catch { /* quota */ } }
  const load = (symbol) => { try { return JSON.parse(storage?.getItem(cacheKey(symbol)) || 'null') } catch { return null } }

  /** Latest ~50 Yahoo news items tagged to the ticker, unscored. */
  async function yahooNews(ticker) {
    const json = JSON.parse(await get('search', { symbol: yahooSymbol(ticker) }, 60_000))
    return (json.news || []).flatMap((n) =>
      n.link && n.title && n.providerPublishTime
        ? [{ id: n.uuid || n.link, url: n.link, headline: n.title, summary: null, source: n.publisher || null,
             published_at: new Date(n.providerPublishTime * 1000).toISOString(), symbols: n.relatedTickers || [] }]
        : [])
  }

  const unCdata = (s) => s.replace(/^<!\[CDATA\[|\]\]>$/g, '').trim()
  const tag = (xml, name) => { const m = new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`).exec(xml); return m ? unCdata(m[1]) : null }
  const unescapeXml = (s) => s && s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")

  /** Items from a Google News RSS document; tagged relevant only if the headline names the ticker/company. */
  function parseGoogleRSS(xml, ticker, companyName, limit) {
    const first = companyName?.split(' ')[0]?.toLowerCase().replace(/[^a-z]/g, '')
    const name = first && first.length >= 4 ? first : null
    const items = [...xml.matchAll(/<item>([\s\S]*?)<\/item>/g)].flatMap((m) => {
      let title = unescapeXml(tag(m[1], 'title')), link = tag(m[1], 'link'), pub = tag(m[1], 'pubDate'), source = unescapeXml(tag(m[1], 'source'))
      const date = pub && new Date(pub)
      if (!title || !link || !date || Number.isNaN(date.getTime())) return []
      if (source && title.endsWith(` - ${source}`)) title = title.slice(0, -(source.length + 3))
      const lower = title.toLowerCase()
      const mentions = ticker && (lower.includes(String(ticker).toLowerCase()) || (name && lower.includes(name)))
      return [{ id: link, url: link, headline: title, summary: null, source, published_at: date.toISOString(), symbols: mentions ? [String(ticker).toUpperCase()] : [] }]
    })
    return items.sort((a, b) => b.published_at.localeCompare(a.published_at)).slice(0, limit)
  }

  /** ~4 weekly windows of Google News, newest `perWindow` of each, so history spans weeks and not one day. */
  async function googleNews(ticker, companyName, { weeks = 4, perWindow = 6, now = new Date() } = {}) {
    const windows = await Promise.all([...Array(weeks).keys()].map(async (w) => {
      const before = new Date(now.getTime() + (1 - 7 * w) * 86_400_000)
      const after = new Date(before.getTime() - 7 * 86_400_000)
      try {
        return parseGoogleRSS(await get('gnews', { symbol: yahooSymbol(ticker), after: dayStr(after), before: dayStr(before) }, 60_000), ticker, companyName, perWindow)
      } catch { return [] }
    }))
    const seen = new Set()
    return windows.flat().filter((a) => !seen.has(a.id) && seen.add(a.id))
  }

  /** Free-text Google News search (used for leadership / supply-chain / sector / macro queries); items are untagged. */
  async function googleSearch(query, { limit = 10 } = {}) {
    return parseGoogleRSS(await get('gsearch', { q: query }, 300_000), '', null, limit)
  }

  return { bars, yahooNews, googleNews, googleSearch, parseNasdaq, parseGoogleRSS }
}
