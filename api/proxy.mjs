// Allow-listed pass-through for the browser: Yahoo/Nasdaq/Google News don't send CORS headers.
// Runs as a Vercel Function in production and via a Vite middleware in `npm run dev`
// (see frontend/vite.config.js). Only the five fixed targets below are reachable (no open proxy),
// and every parameter is validated before it is placed in an upstream URL.
// (gsearch takes a free-text query, restricted to a conservative character set and length.)
const UA = 'Mozilla/5.0'
const SYMBOL = /^[A-Za-z0-9.\-^=]{1,12}$/
const DAY = /^\d{4}-\d{2}-\d{2}$/

const QUERY = /^[\w\s"'().&,:\-–]{1,300}$/ // Google News search syntax: words, quotes, OR, parentheses, when:7d

function upstream(target, q) {
  const symbol = q.symbol
  if (target !== 'gsearch' && !SYMBOL.test(symbol || '')) throw new Error('bad symbol')
  switch (target) {
    case 'gsearch': {
      if (typeof q.q !== 'string' || !QUERY.test(q.q)) throw new Error('bad query')
      return `https://news.google.com/rss/search?q=${encodeURIComponent(q.q)}&hl=en-US&gl=US&ceid=US:en`
    }
    case 'chart':
      return `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=1y&interval=1d`
    case 'search':
      return `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(symbol)}&newsCount=50&quotesCount=0`
    case 'nasdaq': {
      if (!['stocks', 'etf'].includes(q.assetclass) || !DAY.test(q.fromdate || '') || !DAY.test(q.todate || '')) throw new Error('bad nasdaq params')
      return `https://api.nasdaq.com/api/quote/${encodeURIComponent(symbol.replace(/-/g, '.'))}/historical?assetclass=${q.assetclass}&limit=400&fromdate=${q.fromdate}&todate=${q.todate}`
    }
    case 'gnews': {
      if (!DAY.test(q.after || '') || !DAY.test(q.before || '')) throw new Error('bad gnews params')
      const query = `${symbol} stock after:${q.after} before:${q.before}`
      return `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=en-US&gl=US&ceid=US:en`
    }
    default:
      throw new Error('unknown target')
  }
}

export default async function handler(req, res) {
  const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams)
  let url
  try {
    url = upstream(q.target, q)
  } catch (e) {
    res.statusCode = 400
    res.setHeader('content-type', 'application/json')
    return res.end(JSON.stringify({ error: e.message }))
  }
  try {
    const r = await fetch(url, { headers: { 'user-agent': UA, accept: '*/*' }, signal: AbortSignal.timeout(15000) })
    res.statusCode = r.status
    res.setHeader('content-type', r.headers.get('content-type') || 'application/octet-stream')
    res.setHeader('cache-control', 'public, s-maxage=60, stale-while-revalidate=300')
    res.end(Buffer.from(await r.arrayBuffer()))
  } catch {
    res.statusCode = 502
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ error: 'upstream unavailable' }))
  }
}
