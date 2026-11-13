import Foundation

/// Event grouping + relationship-aware relevance for news. Mirrors frontend/src/lib/local/news.js; both load
/// the same curated data (data/news_profiles.json, synced by scripts/sync_news_profiles.py). Keep them in step.

// MARK: - Curated data

private struct ProfilesFile: Decodable {
    struct Channel: Decodable { let relevance: Double?; let weight: Double; let sign: Double }
    struct Sector: Decodable {
        let label: String
        let sectorTerms: [String], supplyTerms: [String], macroTerms: [String], inverseTerms: [String]
    }
    struct Entry: Decodable {
        let sector: String?
        let aliases: [String]?, people: [String]?, supply: [String]?, competitors: [String]?, chronic: [String]?
    }
    let channels: [String: Channel]
    let sectors: [String: Sector]
    let tickers: [String: Entry]
}

/// Everything we know about how news relates to one ticker (curated overrides + sector template + catalog name).
struct NewsProfile: Equatable {
    let ticker: String
    let aliases: [String], people: [String], supply: [String], competitors: [String], chronic: [String]
    let sectorTerms: [String], macro: [String], inverse: [String]
    let sectorLabel: String?
}

/// How a headline bears on a ticker. `sign` maps the headline's text sentiment onto the ticker
/// (+1 same direction, -1 inverse, e.g. a competitor's bad news).
struct NewsExposure: Equatable {
    let channel: String
    let relevance: Double
    let weight: Double
    let sign: Double
}

struct NewsEvent {
    let id: Int
    let articles: [Article]
    let outlets: Int
    let value: Double          // weighted mean of members' signed, source-weighted sentiment
    var weight: Double         // channel weight x coverage boost (x storyline damping)
    let time: Date             // first report
    let latest: Date
    let channel: String
    let relevance: Double
    let rep: Article           // trusted outlet first, then newest
    let tokens: Set<String>    // informative words of all member headlines (for storyline detection)
    var damp: Double = 1       // 1/sqrt(rank) within a bursting storyline, floored; 1 otherwise
    var storyline: String? = nil
    var storyRank: Int = 1
    var size: Int { articles.count }
}

struct ExposedArticle {
    let article: Article
    let exposure: NewsExposure
    let time: Date
    let value: Double
}

enum NewsEvents {
    static let eventWindow: TimeInterval = 48 * 3600
    private static let directMin = 0.35 // the default minimum relevance

    private static let file: ProfilesFile? = {
        guard let url = Bundle.main.url(forResource: "NewsProfiles", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ProfilesFile.self, from: data)
    }()

    static var isLoaded: Bool { file != nil }

    private static let genericFirstWords: Set<String> = ["general", "united", "american", "first", "national", "international", "global", "southern", "western", "eastern", "northern", "pacific", "great", "new", "bank"]

    private static func cleanName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "\\b(inc|corp|corporation|co|company|ltd|plc|holdings|group|incorporated|class [a-c]|the)\\b\\.?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[.,]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func profile(for ticker: String, companyName: String? = nil) -> NewsProfile {
        let sym = ticker.uppercased()
        let entry = file?.tickers[sym]
        let sector = entry?.sector.flatMap { file?.sectors[$0] }
        var aliases = (entry?.aliases ?? []).map { $0.lowercased() }
        if let companyName {
            let full = cleanName(companyName)
            if !full.isEmpty, !aliases.contains(full) { aliases.append(full) }
            if let first = full.split(separator: " ").first.map(String.init), first.count >= 5,
               !genericFirstWords.contains(first), !aliases.contains(first) { aliases.append(first) }
        }
        func lower(_ xs: [String]?) -> [String] { (xs ?? []).map { $0.lowercased() } }
        return NewsProfile(
            ticker: sym, aliases: aliases, people: lower(entry?.people),
            supply: lower((entry?.supply ?? []) + (sector?.supplyTerms ?? [])),
            competitors: lower(entry?.competitors), chronic: lower(entry?.chronic),
            sectorTerms: lower(sector?.sectorTerms), macro: lower(sector?.macroTerms), inverse: lower(sector?.inverseTerms),
            sectorLabel: sector?.label
        )
    }

    // MARK: - Term matching

    private static func isAlnum(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }

    /// Whole-term match (term bounded by non-alphanumerics), identical semantics to the JS `hasTerm`.
    static func hasTerm(_ text: String, _ term: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let r = text.range(of: term, range: range) {
            let beforeOK = r.lowerBound == text.startIndex || !isAlnum(text[text.index(before: r.lowerBound)])
            let afterOK = r.upperBound == text.endIndex || !isAlnum(text[r.upperBound])
            if beforeOK && afterOK { return true }
            range = text.index(after: r.lowerBound)..<text.endIndex
        }
        return false
    }

    // MARK: - Exposure

    static func exposure(profile: NewsProfile, headline: String, symbols: [String] = []) -> NewsExposure? {
        let h = headline.lowercased()
        let direct = Analytics.relevance(ticker: profile.ticker, headline: headline, symbols: symbols, aliases: profile.aliases)
        // A headline that is both tagged with the ticker and names the company (0.85+) counts in full; tag-only or
        // mention-only articles (e.g. Yahoo tagging a retirement story with five tickers) count proportionally less.
        let directWeight = min(1, direct / 0.8)
        var best: NewsExposure? = direct > 0 ? NewsExposure(channel: "direct", relevance: direct, weight: directWeight, sign: 1) : nil
        // Naming the company (or being tagged with its ticker) is direct news, whatever else the headline also touches.
        if direct >= directMin { return best }
        func consider(_ channel: String, _ terms: [String], sign: Double? = nil) {
            guard let c = file?.channels[channel], let relevance = c.relevance, terms.contains(where: { hasTerm(h, $0) }) else { return }
            if best == nil || relevance > best!.relevance {
                best = NewsExposure(channel: channel, relevance: relevance, weight: c.weight, sign: sign ?? c.sign)
            }
        }
        consider("people", profile.people)
        consider("supply", profile.supply)
        consider("sector", profile.sectorTerms)
        consider("competitor", profile.competitors)
        consider("macro", profile.macro)
        consider("macro", profile.inverse, sign: -(file?.channels["macro"]?.sign ?? 1))
        return best
    }

    // MARK: - Headline tokens

    private static let stop: Set<String> = Set((
        "a an the and or but of to in on at for from by with as is are was were be been it its this that these those will would could may might can "
        + "after before amid over under into than then so not no new says say said report reports reported reportedly news update updates today week here why how what who when "
        + "stock stocks share shares investors investor market markets wall street analyst analysts vs per via more most "
        + "co corp inc ltd plc nyse nasdaq"
    ).split(separator: " ").map(String.init))

    private static func stem(_ w: String) -> String {
        if w.count > 5 && w.hasSuffix("ing") { return String(w.dropLast(3)) }
        if w.count > 4 && w.hasSuffix("ed") { return String(w.dropLast(2)) }
        if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: "[a-z0-9]+(?:\\.\\d+)?")

    /// Informative tokens of a headline: publisher suffix, filler words and the company's own names removed.
    static func headlineTokens(_ headline: String, ignore: Set<String> = []) -> Set<String> {
        let base = Analytics.stripPublisherSuffix(headline).lowercased()
            .replacingOccurrences(of: "(?<=\\d),(?=\\d{3})", with: "", options: .regularExpression)
            .replacingOccurrences(of: "['’]s\\b", with: "", options: .regularExpression)
        var out = Set<String>()
        let ns = base as NSString
        for m in tokenRegex.matches(in: base, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: m.range)
            if stop.contains(raw) { continue }
            let w = stem(raw)
            if w.count < 2 || stop.contains(w) || ignore.contains(w) { continue }
            out.insert(w)
        }
        return out
    }

    /// Words belonging to the company itself (every headline has them, so they say nothing about *which* event).
    static func ignoreTokens(_ profile: NewsProfile) -> Set<String> {
        var out: Set<String> = [profile.ticker.lowercased()]
        for alias in profile.aliases {
            let ns = alias as NSString
            for m in tokenRegex.matches(in: alias, range: NSRange(location: 0, length: ns.length)) {
                out.insert(stem(ns.substring(with: m.range)))
            }
        }
        return out
    }

    /// Same event if the headlines share most of their informative words (rewrites and syndication).
    static func sameEvent(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let inter = a.intersection(b).count
        if inter >= 1 && inter == a.count && inter == b.count { return true } // identical informative words, however few
        if inter < 2 { return false }
        let jaccard = Double(inter) / Double(a.count + b.count - inter)
        let overlap = Double(inter) / Double(min(a.count, b.count))
        return jaccard >= 0.5 || (overlap >= 0.75 && inter >= 3)
    }

    /// One event's weight: 1 for a single outlet, +0.5*ln(outlets) beyond that, capped (echo != importance, breadth != nothing).
    static func coverageBoost(_ outlets: Int) -> Double { min(2.5, 1 + 0.5 * log(Double(max(outlets, 1)))) }

    // MARK: - Grouping

    /// Groups exposed articles into events (single-link within 48h), newest first.
    static func groupEvents(_ items: [ExposedArticle], ignore: Set<String>) -> [NewsEvent] {
        let toks = items.map { headlineTokens($0.article.headline, ignore: ignore) }
        var parent = Array(items.indices)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        for i in items.indices {
            for j in items.indices where j > i {
                if abs(items[i].time.timeIntervalSince(items[j].time)) <= eventWindow, sameEvent(toks[i], toks[j]) {
                    parent[find(i)] = find(j)
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in items.indices { groups[find(i), default: []].append(i) }
        return groups.values.map { idxs in
            let members = idxs.map { items[$0] }
            let wSum = members.reduce(0) { $0 + $1.exposure.weight }
            let outlets = Set(members.map { Analytics.normalize($0.article.source ?? "").isEmpty ? String($0.article.id) : Analytics.normalize($0.article.source ?? "") }).count
            let rep = members.sorted {
                let a = $0.article.sourceWeight ?? 1, b = $1.article.sourceWeight ?? 1
                return a != b ? a > b : $0.time > $1.time
            }[0]
            let top = members.reduce(members[0]) { $1.exposure.weight > $0.exposure.weight ? $1 : $0 }
            return NewsEvent(
                id: rep.article.id,
                articles: members.map(\.article),
                outlets: outlets,
                value: members.reduce(0) { $0 + $1.exposure.weight * $1.value } / wSum,
                weight: top.exposure.weight * coverageBoost(outlets),
                time: members.map(\.time).min()!,
                latest: members.map(\.time).max()!,
                channel: top.exposure.channel,
                relevance: members.map(\.exposure.relevance).max()!,
                rep: rep.article,
                tokens: idxs.reduce(into: Set<String>()) { $0.formUnion(toks[$1]) }
            )
        }.sorted { $0.latest > $1.latest }
    }

    // MARK: - Storylines: one big story, told from many angles

    static let storyWindow: TimeInterval = 72 * 3600
    private enum Story {
        static let minEvents = 30, floor = 0.25
        static let minLocal = 4, minRate = 0.12, minBurst = 3.0, minOutside = 20   // enough older events to require a real burst
        static let noBaselineLocal = 6, noBaselineRate = 0.15                      // a story fills the whole sample: stoplists + stricter counts
    }

    private static let background: Set<String> = {
        struct File: Decodable { let tokens: [String] }
        guard let url = Bundle.main.url(forResource: "NewsBackground", withExtension: "json"),
              let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(f.tokens)
    }()

    /// Words that can never be a storyline for this ticker: ordinary headline vocabulary across tickers and the ticker's own
    /// topical vocabulary. People are deliberately not excluded (a leadership story is the canonical storyline), except a
    /// company's chronic newsmakers (Musk at Tesla).
    static func storylineExclusions(_ profile: NewsProfile) -> Set<String> {
        var out = background
        for term in profile.aliases + profile.supply + profile.sectorTerms + profile.macro + profile.inverse + profile.competitors {
            out.formUnion(headlineTokens(term))
        }
        for person in profile.people { out.subtract(headlineTokens(person)) }
        for t in profile.chronic { out.insert(t) }
        return out
    }

    private static func lowerBound(_ a: [TimeInterval], _ x: TimeInterval) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < x { lo = m + 1 } else { hi = m } }
        return lo
    }

    /// Different pieces about one developing story are different *events*, but together they would dominate the sentiment.
    /// A term is a storyline when it bursts: in >= `minLocal` events within +/-72h of an event and >= 12% of them, and >= 3x as
    /// common there as in the rest of the set (steady words never qualify; Title Case doesn't matter). The k-th event of a
    /// storyline within the window counts for 1/sqrt(k) of its weight (floor 0.25). Mirrors dampStorylines in news.js.
    static func dampStorylines(_ events: [NewsEvent], exclude: Set<String> = []) -> [NewsEvent] {
        let n = events.count
        guard n >= Story.minEvents else { return events }
        let t = events.map { $0.time.timeIntervalSince1970 }
        let order = events.indices.sorted { t[$0] != t[$1] ? t[$0] < t[$1] : $0 < $1 }
        let times = order.map { t[$0] }
        var byToken: [String: [TimeInterval]] = [:]
        for i in order { for tok in events[i].tokens { byToken[tok, default: []].append(t[i]) } }
        let w = storyWindow
        var out = events
        for (i, e) in events.enumerated() {
            let nbr = lowerBound(times, t[i] + w + 0.001) - lowerBound(times, t[i] - w)
            let outsideN = n - nbr
            let hasBaseline = outsideN >= Story.minOutside
            let minLocal = hasBaseline ? Story.minLocal : Story.noBaselineLocal
            let minRate = hasBaseline ? Story.minRate : Story.noBaselineRate
            var best: (token: String, local: Int, ts: [TimeInterval])?
            for tok in e.tokens.sorted() where !exclude.contains(tok) {   // sorted so ties resolve identically to JS
                guard let ts = byToken[tok], ts.count >= minLocal else { continue }
                let local = lowerBound(ts, t[i] + w + 0.001) - lowerBound(ts, t[i] - w)
                if local < minLocal || Double(local) / Double(nbr) < minRate { continue }
                if hasBaseline, (Double(local) / Double(nbr)) / (Double(ts.count - local) / Double(outsideN) + 0.02) < Story.minBurst { continue }
                if best == nil || local > best!.local { best = (tok, local, ts) }
            }
            guard let b = best else { continue }
            let earlier = lowerBound(b.ts, t[i]) - lowerBound(b.ts, t[i] - w)
            let sameTime = events.indices.filter { $0 < i && t[$0] == t[i] && events[$0].tokens.contains(b.token) }.count
            let rank = 1 + earlier + sameTime
            let damp = max(Story.floor, 1 / Double(rank).squareRoot())
            out[i].damp = damp
            out[i].storyline = b.token
            out[i].storyRank = rank
            out[i].weight = e.weight * damp
        }
        return out
    }

    // MARK: - Searches that find the indirect news

    private static func orQuery(_ terms: [String], _ n: Int) -> String {
        terms.prefix(n).map { $0.contains(where: \.isWhitespace) ? "\"\($0)\"" : $0 }.joined(separator: " OR ")
    }

    /// Google News queries per channel (leadership/supply/sector/macro); results are kept only if `exposure` recognises them.
    static func indirectQueries(_ profile: NewsProfile) -> [String] {
        var qs: [String] = []
        if let lead = profile.aliases.first {
            qs.append(orQuery(["\(lead) ceo", "\(lead) chief executive", "\(lead) cfo"] + profile.people, 5))
        }
        if !profile.supply.isEmpty { qs.append(orQuery(profile.supply, 6)) }
        if !profile.sectorTerms.isEmpty { qs.append(orQuery(profile.sectorTerms, 4)) }
        if !profile.macro.isEmpty { qs.append(orQuery(profile.macro, 4)) }
        return qs.map { "\($0) when:7d" }
    }
}
