// Shadow evaluation on LIVE news (needs network + the real model; skipped otherwise):
//   SHADOW=1 [SHADOW_TICKERS=AAPL,NVDA] [SHADOW_THRESHOLD=0.5] [SHADOW_OUT=/path/report.json] npx vitest run semantic.shadow
// For each ticker it groups the same cached articles twice, lexical-only and lexical+semantic, and writes what the
// semantic stage merged or nearly merged (with cosine, entity, time and score), so thresholds can be judged on real headlines.
import { describe, it } from 'vitest'
import { writeFileSync } from 'node:fs'
import handler from '../../../../api/proxy.mjs'
import { createLocalApi } from './client'
import { createEmbedder } from './embeddings'

const memStorage = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) } }
const viaProxy = async (url) => {
  const query = Object.fromEntries(new URL(url, 'http://x').searchParams)
  const res = { statusCode: 200, headers: {}, setHeader() {}, end(b) { this.body = b } }
  await handler({ query }, res)
  return { ok: res.statusCode < 300, status: res.statusCode, text: async () => String(res.body ?? '') }
}
const offline = async () => { throw new TypeError('offline: use the cache') }

describe.runIf(process.env.SHADOW)('semantic event grouping on live news', () => {
  it('reports lexical vs semantic grouping', async () => {
    const tickers = (process.env.SHADOW_TICKERS || 'AAPL,NVDA,TSLA,META,MSFT,AMZN,GOOGL,JPM,BA,INTC,PFE,XOM').split(',')
    const threshold = process.env.SHADOW_THRESHOLD ? Number(process.env.SHADOW_THRESHOLD) : undefined
    const embedder = createEmbedder()
    const report = []
    for (const t of tickers) {
      const storage = memStorage()
      const live = createLocalApi({ fetchImpl: viaProxy, storage, embedder, semanticMode: 'off' })
      const params = { days: 30, min_relevance: 0.2, limit: 1000 }
      await live.get(`/api/news/${t}`, { params })
      for (let i = 0; i < 120; i++) { // wait for the background embedding pass
        const a = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
        if (a.length && a.every((x) => x.emb)) break
        await new Promise((r) => setTimeout(r, 1000))
      }
      const cached = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
      const off = createLocalApi({ fetchImpl: offline, storage, embedder: null, semanticMode: 'off' })
      const on = createLocalApi({ fetchImpl: offline, storage, embedder: null, semanticMode: 'on', semanticThreshold: threshold })
      const eventsOff = (await off.get(`/api/news/${t}`, { params })).data
      const eventsOn = (await on.get(`/api/news/${t}`, { params })).data
      const log = on.debug.decisions(t)
      report.push({ ticker: t, articles: cached.length, embedded: cached.filter((x) => x.emb).length, eventsLexical: eventsOff.length, eventsSemantic: eventsOn.length,
        merges: log.filter((e) => e.type === 'semantic-merge'), nearMisses: log.filter((e) => e.type === 'near-miss') })
    }
    writeFileSync(process.env.SHADOW_OUT || '/tmp/shadow-report.json', JSON.stringify(report, null, 1))
  }, 1_200_000)
})
