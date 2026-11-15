import Foundation

/// Semantic event matching: decides whether two articles the lexical rules did NOT link still describe the same event, from
/// sentence embeddings + shared entities + closeness in time. Mirrors frontend/src/lib/local/semantic.js; keep them in step.
/// Lexical links always win and are never undone; this only adds links, conservatively (average linkage, high threshold).
enum NewsSemantic {
    private static var cfg: NewsConfig.Events.Semantic { NewsConfig.shared.events.semantic }
    private static let magnitude: [String: Double] = ["trillion": 1e12, "billion": 1e9, "bn": 1e9, "b": 1e9, "million": 1e6, "mn": 1e6, "m": 1e6, "thousand": 1e3, "k": 1e3]
    private static let genericCaps: Set<String> = ["ceo", "cfo", "coo", "cto", "ipo", "q1", "q2", "q3", "q4"] // capitalised, but in half of all headlines

    /// One merge or near miss, with the numbers behind it (the on-device counterpart of `newsedge.api.debug.decisions`).
    struct Decision: Equatable {
        enum Kind: String { case merge = "semantic-merge", nearMiss = "near-miss" }
        let kind: Kind
        let score: Double, threshold: Double
        let a: String, b: String
        let jaccard: Double?, overlap: Double?
        let cosine: Double, entity: Double?, dtHours: Double, pairScore: Double
        var size: Int? = nil
        var applied = false
    }

    struct Merge { let members: [Int]; let score: Double }

    // MARK: - Embeddings

    private static let lock = NSLock()
    nonisolated(unsafe) private static var vectors: [String: [Float]] = [:] // emb string -> vector (dequantising 300 articles per call is wasteful)

    static func vector(of article: Article) -> [Float]? {
        guard let emb = article.emb else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let v = vectors[emb] { return v }
        guard let v = EmbeddingCodec.dequantize(emb) else { return nil }
        if vectors.count > 20_000 { vectors.removeAll() }
        vectors[emb] = v
        return v
    }

    // MARK: - Signals

    /// Linear interpolation over events.semantic.time_similarity ([[hours, similarity], ...]); 0 beyond the last point.
    static func timeSimilarity(_ dt: TimeInterval, points: [[Double]]? = nil) -> Double {
        let pts = points ?? cfg.timeSimilarity
        let h = abs(dt) / 3600
        guard let last = pts.last else { return 0 }
        if h > last[0] { return 0 }
        for i in 1..<pts.count where h <= pts[i][0] {
            let (h0, v0, h1, v1) = (pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1])
            return v0 + (v1 - v0) * (h - h0) / (h1 - h0)
        }
        return last[1]
    }

    private static let numberRegex = try! NSRegularExpression(pattern: #"([$€£])?\s?(\d[\d,]*(?:\.\d+)?)\s?(trillion|billion|million|thousand|bn|mn|%|percent|[bmk]\b)?"#)
    private static let publisherSuffix = try! NSRegularExpression(pattern: #"\s*[-–|]\s*[A-Za-z][\w\s.&]{1,40}$"#)
    private static let possessive = try! NSRegularExpression(pattern: #"['’]s\b"#)
    private static let edgePunct = try! NSRegularExpression(pattern: #"^[^A-Za-z0-9$]+|[^A-Za-z0-9]+$"#)

    private static func replace(_ re: NSRegularExpression, in s: String, with t: String = "") -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }
    /// JS-style number text: 5, 1.5, 1500000000 (no trailing ".0").
    private static func num(_ x: Double) -> String { x == x.rounded() && abs(x) < 1e15 ? String(Int64(x)) : "\(x)" }
    private static func isCap(_ w: String) -> Bool { w.unicodeScalars.first.map { $0.value >= 65 && $0.value <= 90 } ?? false }

    /// What a headline is about beyond the company itself: amounts ("$5 billion", "20%"), curated profile terms, and capitalised
    /// phrases (skipped for Title Case headlines, where capitals say nothing). Lower-cased. `ignore` = the company's own name tokens.
    static func entities(of headline: String, terms: [String] = [], ignore: Set<String> = []) -> Set<String> {
        var out = Set<String>()
        let text = replace(possessive, in: replace(publisherSuffix, in: headline))
        let lower = text.lowercased()
        let ns = lower as NSString
        for m in numberRegex.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            guard let digits = group(2), let n = Double(digits.replacingOccurrences(of: ",", with: "")) else { continue }
            let unit = group(3)
            if unit == "%" || unit == "percent" { out.insert("\(num(n))%") }
            else if let unit, let k = magnitude[unit] { out.insert("#\(num(n * k))") }
            else if group(1) != nil || n >= 1000 { out.insert("#\(num(n))") } // "$5", "200,000"; bare small numbers are dates and counts
        }
        for t in terms where NewsEvents.hasTerm(lower, t) { out.insert(t) }
        let words = text.split(whereSeparator: \.isWhitespace).map { replace(edgePunct, in: String($0)) }.filter { !$0.isEmpty }
        let long = words.filter { $0.count > 3 }
        guard !long.isEmpty, Double(long.filter(isCap).count) / Double(long.count) < 0.7 else { return out } // Title Case: capitals say nothing
        var i = 0
        while i < words.count {
            guard isCap(words[i]) else { i += 1; continue }
            var j = i
            while j + 1 < words.count && isCap(words[j + 1]) { j += 1 }
            let run = words[i...j].map { $0.lowercased() }
            defer { i = j + 1 }
            if run.count == 1 && (j == 0 || run[0].count < 2) { continue } // a sentence-initial word alone is just a word
            let phrase = run.filter { !ignore.contains($0) && !genericCaps.contains($0) }
            if !phrase.isEmpty { out.insert(phrase.joined(separator: " ")) }
        }
        return out
    }

    /// Shared entities over the smaller set (a headline that mentions fewer things is not penalised); nil if either has none.
    static func entitySimilarity(_ a: Set<String>, _ b: Set<String>) -> Double? {
        if a.isEmpty || b.isEmpty { return nil }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    /// 0.65 semantic + 0.20 entity + 0.15 time; with no entities on one side the entity term is dropped and the rest renormalised.
    static func pairScore(cosine: Double, entity: Double?, dt: TimeInterval) -> Double {
        let w = cfg.weights, time = timeSimilarity(dt)
        guard let entity else { return (w.semantic * cosine + w.time * time) / (w.semantic + w.time) }
        return w.semantic * cosine + w.entity * entity + w.time * time
    }

    // MARK: - Merging

    private struct Pair { let i: Int, j: Int; let cosine: Double; let entity: Double?; let dt: TimeInterval; let score: Double }

    /// `groups`: arrays of item indexes the lexical rules already linked. Returns the semantic merges. Average linkage over all
    /// cross pairs that have embeddings (a pair more than `window` apart scores 0), so a merge needs the groups as a whole to be
    /// close, not one lucky pair. `log` receives every merge and every near miss.
    static func merges(items: [ExposedArticle], groups: [[Int]], terms: [String] = [], ignore: Set<String> = [], window: TimeInterval,
                       threshold: Double? = nil, lexical: (Int, Int) -> (jaccard: Double, overlap: Double)? = { _, _ in nil },
                       log: ((Decision) -> Void)? = nil) -> [Merge] {
        let threshold = threshold ?? cfg.threshold
        let n = items.count
        let vec = items.map { vector(of: $0.article) }
        guard vec.compactMap({ $0 }).count >= 2 else { return [] }
        let ents = items.indices.map { vec[$0] != nil ? entities(of: items[$0].article.headline, terms: terms, ignore: ignore) : [] }
        var gid = [Int](repeating: 0, count: n)
        for (k, g) in groups.enumerated() { for i in g { gid[i] = k } }
        var pairs: [Int: Pair] = [:] // i * n + j (i < j): embedded pairs in different groups inside the window
        for i in 0..<n {
            guard let vi = vec[i] else { continue }
            for j in (i + 1)..<max(n, i + 1) {
                guard let vj = vec[j], gid[i] != gid[j] else { continue }
                let dt = abs(items[i].time.timeIntervalSince(items[j].time))
                if dt > window { continue }
                let cos = EmbeddingCodec.cosine(vi, vj), ent = entitySimilarity(ents[i], ents[j])
                pairs[i * n + j] = Pair(i: i, j: j, cosine: cos, entity: ent, dt: dt, score: pairScore(cosine: cos, entity: ent, dt: dt))
            }
        }
        if pairs.isEmpty { return [] }
        func link(_ A: [Int], _ B: [Int]) -> (mean: Double, best: Pair?) { // average over embedded cross pairs; out-of-window pairs count as 0
            var sum = 0.0, count = 0
            var best: Pair?
            for i in A { for j in B {
                guard vec[i] != nil, vec[j] != nil else { continue }
                count += 1
                if let p = pairs[min(i, j) * n + max(i, j)] {
                    sum += p.score
                    if best == nil || p.score > best!.score { best = p }
                }
            } }
            return (count > 0 ? sum / Double(count) : -1, best)
        }
        func decision(_ kind: Decision.Kind, _ score: Double, _ p: Pair) -> Decision {
            let lex = lexical(p.i, p.j)
            return Decision(kind: kind, score: score, threshold: threshold, a: items[p.i].article.headline, b: items[p.j].article.headline,
                            jaccard: lex?.jaccard, overlap: lex?.overlap, cosine: p.cosine, entity: p.entity, dtHours: p.dt / 3600, pairScore: p.score)
        }
        var cur = groups
        var out: [Merge] = []
        while true {
            var top: (a: Int, b: Int, mean: Double, best: Pair)?
            for a in cur.indices { for b in (a + 1)..<max(cur.count, a + 1) {
                if cur[a].isEmpty || cur[b].isEmpty { continue }
                let (mean, best) = link(cur[a], cur[b])
                if let best, mean >= threshold, top == nil || mean > top!.mean { top = (a, b, mean, best) }
            } }
            guard let t = top else { break }
            let members = cur[t.a] + cur[t.b]
            out.append(Merge(members: members, score: t.mean))
            if let log { var d = decision(.merge, t.mean, t.best); d.size = members.count; log(d) }
            cur[t.a] = members
            cur[t.b] = []
        }
        if let log { // the close calls, for tuning: group pairs that fell just short
            let floor = threshold - cfg.nearMissMargin
            for a in cur.indices { for b in (a + 1)..<max(cur.count, a + 1) {
                if cur[a].isEmpty || cur[b].isEmpty { continue }
                let (mean, best) = link(cur[a], cur[b])
                if let best, mean >= floor, mean < threshold { log(decision(.nearMiss, mean, best)) }
            } }
        }
        return out
    }

    // MARK: - Storylines

    /// One storyline decision in `shadow` or `on` mode (the on-device counterpart of the `semantic-storyline` log entries on web).
    struct StoryDecision: Equatable {
        let headline: String, label: String
        let rank: Int, local: Int, tokenRank: Int
        let damp: Double, tokenDamp: Double
        let related: [String]
        let applied: Bool
        let mode: String
    }

    struct Story { let rank: Int; let local: Int; let label: String; let similar: [Int] }

    /// Unit-length mean of the members' embeddings (an event's "meaning"); nil if none of them is embedded.
    static func eventVector(_ event: NewsEvent) -> [Float]? {
        var sum: [Float]?
        var count = 0
        for a in event.articles {
            guard let v = vector(of: a) else { continue }
            if sum == nil { sum = [Float](repeating: 0, count: v.count) }
            guard sum!.count == v.count else { continue }
            for i in v.indices { sum![i] += v[i] }
            count += 1
        }
        guard count > 0, let s = sum else { return nil }
        let norm = s.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return s.map { $0 / (norm > 0 ? norm : 1) }
    }

    private static func lowerBound(_ a: [TimeInterval], _ x: TimeInterval) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < x { lo = m + 1 } else { hi = m } }
        return lo
    }

    /// The same burst test as token storylines, with "contains the word" replaced by "means about the same as this event": for each
    /// event, the events within +/-`window` whose meaning is close (cosine >= `similarity` AND a shared entity; with none in common, the
    /// stricter `noSharedEntityCosine`) form its story. It is a storyline if big enough, a big enough share of the window and several
    /// times denser there than elsewhere. Anchored per event, never chained. Mirrors semanticStorylines in semantic.js.
    static func storylines(_ events: [NewsEvent], window: TimeInterval, terms: [String] = [], ignore: Set<String> = [], exclude: Set<String> = [],
                           similarity: Double? = nil, noEntityCosine: Double? = nil) -> [Story?] {
        let sl = NewsConfig.shared.storylines
        let similarity = similarity ?? sl.semantic.similarity, noEntityCosine = noEntityCosine ?? sl.semantic.noSharedEntityCosine
        var out = [Story?](repeating: nil, count: events.count)
        var vec: [Int: [Float]] = [:]
        for i in events.indices { if let v = eventVector(events[i]) { vec[i] = v } }
        let idx = events.indices.filter { vec[$0] != nil }
        let n = idx.count
        guard n >= sl.minEvents else { return out }
        var ents: [Int: Set<String>] = [:]
        for i in idx { ents[i] = events[i].articles.reduce(into: Set<String>()) { $0.formUnion(entities(of: $1.headline, terms: terms, ignore: ignore)) } }
        let t = events.map { $0.time.timeIntervalSince1970 }
        let times = idx.sorted { t[$0] != t[$1] ? t[$0] < t[$1] : $0 < $1 }.map { t[$0] }
        for i in idx {
            let nbr = lowerBound(times, t[i] + window + 0.001) - lowerBound(times, t[i] - window), outsideN = n - nbr
            let hasBaseline = outsideN >= sl.minOutside
            let minLocal = hasBaseline ? sl.minLocal : sl.noBaselineLocal, minRate = hasBaseline ? sl.minRate : sl.noBaselineRate
            var local = 1, outside = 0, earlier = 0
            var similar: [Int] = []
            for j in idx where j != i {
                let cos = EmbeddingCodec.cosine(vec[i]!, vec[j]!)
                if cos < similarity { continue }
                let es = entitySimilarity(ents[i]!, ents[j]!) ?? 0
                if es == 0 && cos < noEntityCosine { continue } // a story needs a named anchor in common, or near-identical meaning
                let dt = t[j] - t[i]
                if abs(dt) <= window {
                    local += 1
                    similar.append(j)
                    if dt < 0 || (dt == 0 && j < i) { earlier += 1 }
                } else { outside += 1 }
            }
            if local < minLocal || Double(local) / Double(nbr) < minRate { continue }
            if hasBaseline, (Double(local) / Double(nbr)) / (Double(outside) / Double(outsideN) + 0.02) < sl.minBurst { continue }
            var counts: [String: Int] = [:] // label: the commonest informative word of the story
            for j in [i] + similar { for tok in events[j].tokens where !exclude.contains(tok) { counts[tok, default: 0] += 1 } }
            let label = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key ?? "related coverage"
            out[i] = Story(rank: 1 + earlier, local: local, label: label, similar: similar)
        }
        return out
    }
}
