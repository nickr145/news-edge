import { describe, expect, it, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import { DIM, cosine, createEmbedder, dequantize, embeddingText, quantize } from './embeddings'
import { createLocalApi } from './client'

const unit = (seed) => { const v = Float32Array.from({ length: DIM }, (_, i) => Math.sin(seed * (i + 1))); const n = Math.hypot(...v); return v.map((x) => x / n) }

describe('embedding helpers', () => {
  it('names the company only when the headline omits it', () => {
    expect(embeddingText("Chipmaker's chief executive steps down", 'NVIDIA Corporation')).toBe("NVIDIA: Chipmaker's chief executive steps down")
    expect(embeddingText('Nvidia posts record revenue', 'NVIDIA Corporation')).toBe('Nvidia posts record revenue')
    expect(embeddingText('Anything', null)).toBe('Anything')
  })
  it('int8 round trip keeps cosine within 0.01', () => {
    const a = unit(1), b = unit(1.01)
    const exact = cosine(a, b)
    expect(Math.abs(cosine(dequantize(quantize(a)), dequantize(quantize(b))) - exact)).toBeLessThan(0.01)
    expect(quantize(a)).toHaveLength(Math.ceil(DIM / 3) * 4) // base64 of 384 bytes
  })
  it('cosine of orthogonal / zero vectors', () => {
    expect(cosine(Float32Array.of(1, 0), Float32Array.of(0, 1))).toBe(0)
    expect(cosine(new Float32Array(2), Float32Array.of(1, 0))).toBe(0)
  })
})

describe('embedder', () => {
  const model = vi.fn(async (texts) => ({ data: Float32Array.from(texts.flatMap((_, i) => [...unit(i + 1)])) }))
  it('loads the model once and returns one vector per text', async () => {
    const load = vi.fn(async () => model)
    const e = createEmbedder({ load })
    const [a, b] = await e.embed(['x', 'y'])
    await e.embed(['z'])
    expect(load).toHaveBeenCalledTimes(1)
    expect(a).toHaveLength(DIM)
    expect(cosine(a, unit(1))).toBeCloseTo(1, 5)
    expect(cosine(b, unit(2))).toBeCloseTo(1, 5)
    expect(await e.embed([])).toEqual([])
  })
  it('returns null on failure and does not retry for a few minutes', async () => {
    let t = 0
    const load = vi.fn(async () => { throw new Error('blocked') })
    const e = createEmbedder({ load, now: () => t })
    expect(await e.embed(['x'])).toBeNull()
    t = 60_000
    expect(await e.embed(['x'])).toBeNull()
    expect(load).toHaveBeenCalledTimes(1)
    t = 6 * 60_000
    await e.embed(['x'])
    expect(load).toHaveBeenCalledTimes(2)
  })
})

describe('background embedding of cached articles', () => {
  const NOW = new Date('2026-11-12T12:00:00Z')
  const memStorage = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) } }
  const yahoo = (items) => async (url) => {
    const target = new URL(url, 'http://x').searchParams.get('target')
    if (target !== 'search') throw new TypeError('down')
    const news = items.map((title) => ({ uuid: title, title, publisher: 'Zacks', link: `https://x.test/${title.replace(/\W/g, '')}`, providerPublishTime: Math.floor(new Date('2026-11-11T10:00:00Z').getTime() / 1000), relatedTickers: ['AAPL'] }))
    return { ok: true, status: 200, text: async () => JSON.stringify({ news }) }
  }
  const flush = () => new Promise((r) => setTimeout(r, 0))

  it('embeds each article once, never delays articles, and keeps vectors out of API output', async () => {
    const storage = memStorage()
    let release
    const gate = new Promise((r) => { release = r })
    const embed = vi.fn(async (texts) => { await gate; return texts.map((_, i) => unit(i + 1)) })
    const api = createLocalApi({ fetchImpl: yahoo(['Apple beats estimates', 'Apple unveils chip']), storage, score: () => 0, companyName: () => 'Apple Inc.', now: () => NOW, embedder: { embed } })
    const { data } = await api.get('/api/news/AAPL', { params: { days: 30, min_relevance: 0.2 } }) // resolves while embedding is still gated
    expect(data.length).toBeGreaterThan(0)
    expect(data.every((a) => !('emb' in a))).toBe(true)
    const stored = () => JSON.parse(storage.getItem('newsedge_news_v1_AAPL'))
    expect(stored().every((a) => !a.emb)).toBe(true)
    release(); await flush(); await flush()
    expect(stored().every((a) => typeof a.emb === 'string')).toBe(true)
    expect(embed.mock.calls[0][0].every((t) => t.length > 0)).toBe(true)
    const calls = embed.mock.calls.length
    await api.get('/api/news/AAPL/sentiment', { params: { days: 7 } }); await flush(); await flush()
    expect(embed.mock.calls.length).toBe(calls) // changing the window never re-embeds
  })

  it('keeps working (lexically) when the model is unavailable', async () => {
    const api = createLocalApi({ fetchImpl: yahoo(['Apple beats estimates']), storage: memStorage(), score: () => 0, companyName: () => 'Apple Inc.', now: () => NOW, embedder: { embed: async () => null } })
    const { data } = await api.get('/api/news/AAPL/sentiment', { params: { days: 7, min_relevance: 0.2 } })
    expect(data.count).toBeGreaterThan(0)
  })
})

// Real model, real tokenizer: `EMBED_LIVE=1 npx vitest run embeddings` (downloads ~23 MB on first run).
describe.runIf(process.env.EMBED_LIVE)('live model matches the Python reference', () => {
  it('quantized ONNX cosine is within 0.05 of sentence-transformers on every fixture pair', async () => {
    const { pairs } = JSON.parse(readFileSync(new URL('../../../../data/embedding_fixtures.json', import.meta.url)))
    const e = createEmbedder()
    const texts = pairs.flatMap((p) => [embeddingText(p.a, p.company), embeddingText(p.b, p.company)])
    const vecs = await e.embed(texts)
    expect(vecs).not.toBeNull()
    pairs.forEach((p, i) => {
      const got = cosine(dequantize(quantize(vecs[2 * i])), dequantize(quantize(vecs[2 * i + 1])))
      expect(Math.abs(got - p.cosine), `${p.a} | ${p.b}`).toBeLessThan(0.05)
    })
  }, 300_000)
})
