// Semantic indirect relevance: decides whether a headline that matches none of a ticker's profile keywords still bears
// on it, by comparing its embedding to anchor sentences built from the profile (one set per indirect channel). Pure
// functions; client.js owns embedding, caching and the mode switch. Keyword matches (news.js exposureOf) always win.
import profiles from '../../data/newsProfiles.json'
import { cosine } from './embeddings'

const CH = profiles.channels
const TERMS_PER_ANCHOR = 3
const ANCHORS_PER_CHANNEL = 2

// Reviewable on purpose: the wording decides what "close to this channel" means. Edit here, the cache key changes with it.
const TEMPLATES = {
  people: (co, _label, terms) => `${co} leadership and executives: ${terms}`,
  supply: (co, _label, terms) => `${co} suppliers, customers and supply chain: ${terms}`,
  sector: (_co, label, terms) => `${label} industry and sector news: ${terms}`,
  competitor: (co, _label, terms) => `${co} competitors and rivals: ${terms}`,
  macro: (_co, label, terms) => `${label} policy, regulation, trade and economy: ${terms}`
}

/** Anchor sentences per indirect channel, from the first TERMS_PER_ANCHOR * ANCHORS_PER_CHANNEL profile terms of each. */
export function anchorTexts(profile) {
  const co = profile.aliases[0] || profile.ticker.toLowerCase()
  const label = (profile.sectorLabel || co).toLowerCase()
  const byChannel = { people: profile.people, supply: profile.supply, sector: profile.sectorTerms, competitor: profile.competitors, macro: profile.macro }
  const out = []
  for (const [channel, list] of Object.entries(byChannel)) {
    const all = [...new Set(list)]
    const terms = all.filter((t) => !all.some((o) => o !== t && o.includes(t))) // "huang" adds nothing next to "jensen huang"
    for (let i = 0; i < terms.length && i < TERMS_PER_ANCHOR * ANCHORS_PER_CHANNEL; i += TERMS_PER_ANCHOR) {
      out.push({ channel, text: TEMPLATES[channel](co, label, terms.slice(i, i + TERMS_PER_ANCHOR).join(', ')) })
    }
  }
  return out
}

/**
 * Scores `vec` against `anchors` ([{channel, vec}]). A channel's score is its best anchor's cosine. `admit` needs the
 * best channel >= threshold AND ahead of the runner-up channel by >= margin (so a headline torn between "supplier" and
 * "sector" is left out). With one channel only, the runner-up counts as 0.
 */
export function semanticExposure(vec, anchors, { threshold, margin }) {
  const best = {}
  for (const a of anchors) best[a.channel] = Math.max(best[a.channel] ?? -1, cosine(vec, a.vec))
  const ranked = Object.entries(best).sort((x, y) => y[1] - x[1])
  if (!ranked.length) return null
  const [channel, cos] = ranked[0]
  const gap = cos - (ranked[1]?.[1] ?? 0)
  const { relevance, weight, sign } = CH[channel]
  return { channel, cosine: cos, margin: gap, admit: cos >= threshold && gap >= margin, exposure: { channel, relevance, weight, sign, embedded: true } }
}
