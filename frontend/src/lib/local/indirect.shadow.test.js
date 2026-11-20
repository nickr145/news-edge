// Shadow evaluation on LIVE news (needs network + the real model; skipped otherwise):
//   SHADOW=1 [SHADOW_TICKERS=NVDA,AAPL] [SHADOW_OUT=/path/report.json] npx vitest run indirect.shadow
// Runs every ticker with threshold 0 / margin 0 so each candidate's best channel, cosine and margin is logged, then writes
// them for offline sweeping (see the plan, Task 5) and hand-labelling of what a given threshold would admit.
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

describe.runIf(process.env.SHADOW)('semantic indirect relevance on live news', () => {
  it('logs every candidate with its best channel', async () => {
    const tickers = (process.env.SHADOW_TICKERS || 'AAPL,NVDA,TSLA,META,MSFT,AMZN,GOOGL,JPM,BA,INTC,PFE,XOM').split(',')
    const embedder = createEmbedder()
    const report = []
    for (const t of tickers) {
      const storage = memStorage()
      const api = createLocalApi({ fetchImpl: viaProxy, storage, embedder, indirectMode: 'shadow', indirectThreshold: 0, indirectMargin: 0 })
      const params = { days: 30, min_relevance: 0.2, limit: 1000 }
      const keyword = (await api.get(`/api/news/${t}`, { params })).data
      for (let i = 0; i < 120; i++) { // wait for the background embedding pass (anchors + articles)
        const a = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
        if (storage.getItem(`newsedge_anchors_v1_${t}`) && a.length && a.every((x) => x.emb)) break
        await new Promise((r) => setTimeout(r, 1000))
      }
      await api.get(`/api/news/${t}`, { params })
      const cached = JSON.parse(storage.getItem(`newsedge_news_v1_${t}`) || '[]')
      report.push({ ticker: t, articles: cached.length, candidates: cached.filter((a) => a.cand).length, keywordEvents: keyword.length,
        scored: api.debug.decisions(t).filter((e) => e.type === 'semantic-indirect') })
    }
    writeFileSync(process.env.SHADOW_OUT || '/tmp/indirect-shadow-report.json', JSON.stringify(report, null, 1))
  }, 1_200_000)
})
