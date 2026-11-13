// Headline tokenizer shared by the app (news.js) and scripts/build_background_tokens.mjs. No imports, so plain Node can load it.
// Mirrored by NewsEvents.headlineTokens in Swift.

export const STOP = new Set(('a an the and or but of to in on at for from by with as is are was were be been it its this that these those will would could may might can '
  + 'after before amid over under into than then so not no new says say said report reports reported reportedly news update updates today week here why how what who when '
  + 'stock stocks share shares investors investor market markets wall street analyst analysts vs per via more most '
  + 'co corp inc ltd plc nyse nasdaq').split(' '))

export const stem = (w) => {
  if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3)
  if (w.length > 4 && w.endsWith('ed')) return w.slice(0, -2)
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1)
  return w
}

/** Informative tokens of a headline: publisher suffix, filler words and the company's own names removed. */
export function headlineTokens(headline, ignore = new Set()) {
  const base = String(headline || '').replace(/\s*[-–|]\s*[A-Za-z][\w\s.&]{1,40}$/, '').toLowerCase()
    .replace(/(?<=\d),(?=\d{3})/g, '').replace(/['’]s\b/g, '')
  const out = new Set()
  for (const raw of base.match(/[a-z0-9]+(?:\.\d+)?/g) || []) {
    if (STOP.has(raw)) continue
    const w = stem(raw)
    if (w.length < 2 || STOP.has(w) || ignore.has(w)) continue
    out.add(w)
  }
  return out
}

