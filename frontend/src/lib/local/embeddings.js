// Sentence embeddings for headlines, computed in the browser (all-MiniLM-L6-v2, quantized ONNX via transformers.js).
// The iOS app runs the same model through Core ML (ios/.../Services/Embedder.swift). Vectors are unit length, so
// cosine similarity is a dot product, and they are stored int8-quantized (base64) next to each cached article.
import config from '../../data/newsConfig.json'

export const DIM = config.embedding.dimension
const MODEL = 'Xenova/all-MiniLM-L6-v2'
const RETRY_MS = 5 * 60_000

/** Headlines that never name the company ("Chipmaker's chief steps down") embed poorly against ones that do, so name it. */
export function embeddingText(headline, companyName) {
  const name = (companyName || '').replace(/[,.]?\s+(inc|corp|corporation|co|ltd|plc|holdings|group)\.?$/i, '').trim()
  if (!config.embedding.prefix_company_when_missing || !name || headline.toLowerCase().includes(name.toLowerCase())) return headline
  return `${name}: ${headline}`
}

/**
 * Direction-only int8: each vector is scaled so its largest component is 127 (a fixed scale wastes the range, since a
 * unit vector in 384 dimensions has components around +/-0.05). The scale is not stored because cosine ignores it.
 * iOS mirrors this exactly.
 */
export function quantize(vec) {
  let max = 0
  for (let i = 0; i < vec.length; i++) max = Math.max(max, Math.abs(vec[i]))
  const k = max ? 127 / max : 0
  let s = ''
  for (let i = 0; i < vec.length; i++) s += String.fromCharCode(Math.round(vec[i] * k) & 255)
  return btoa(s)
}

export function dequantize(b64) {
  const s = atob(b64), out = new Float32Array(s.length)
  for (let i = 0; i < s.length; i++) out[i] = ((s.charCodeAt(i) << 24) >> 24) / 127 // sign-extend the int8
  return out
}

/** Cosine similarity, normalising because dequantized vectors are not unit length. */
export function cosine(a, b) {
  let d = 0, x = 0, y = 0
  for (let i = 0; i < a.length; i++) { d += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i] }
  return x && y ? d / Math.sqrt(x * y) : 0
}

async function loadTransformers() {
  const { pipeline } = await import('@huggingface/transformers') // its own chunk: only fetched once an embedding is needed
  return pipeline('feature-extraction', MODEL, { dtype: 'q8' })
}

/**
 * Lazy, single-flight embedder. `embed(texts)` resolves to one Float32Array per text, or null when the model is
 * unavailable (offline, blocked, unsupported browser): callers keep working on the lexical path. A failed load is
 * not retried for a few minutes so a blocked CDN cannot turn every refresh into a download attempt.
 */
export function createEmbedder({ load = loadTransformers, now = Date.now } = {}) {
  let model = null, failedAt = -Infinity
  const ready = () => {
    if (model) return model
    if (now() - failedAt < RETRY_MS) return null
    model = load().catch(() => { failedAt = now(); model = null; return null })
    return model
  }
  return {
    async embed(texts) {
      if (!texts.length) return []
      const m = await ready()
      if (!m) return null
      try {
        const out = await m(texts, { pooling: 'mean', normalize: true })
        return texts.map((_, i) => Float32Array.from(out.data.slice(i * DIM, (i + 1) * DIM)))
      } catch { return null }
    }
  }
}
