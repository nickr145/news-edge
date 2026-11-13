import Foundation
import Testing
@testable import NewsEdge

/// Same scenarios and expectations as frontend/src/lib/local/news.test.js: the two implementations must agree.
struct NewsEventsTests {
    private static let t0 = Date(timeIntervalSince1970: 1_794_484_800)
    private func ignore(_ t: String, _ name: String) -> Set<String> {
        NewsEvents.ignoreTokens(NewsEvents.profile(for: t, companyName: name))
    }
    private func item(_ headline: String, source: String = "X", hours: Double = 0, value: Double = 0.5) -> ExposedArticle {
        let article = Article(id: abs(headline.hashValue) &+ abs(source.hashValue), url: "u", headline: headline, summary: nil, body: nil,
                              source: source, publishedAt: Self.t0.addingTimeInterval(-hours * 3600), sentimentLabel: nil, compound: nil,
                              relevanceScore: nil, sourceWeight: 1, nearEarnings: nil, isSecFiling: nil)
        return ExposedArticle(article: article, exposure: NewsExposure(channel: "direct", relevance: 0.85, weight: 1, sign: 1),
                              time: article.publishedAt, value: value)
    }

    @Test func profilesLoadAndEveryCatalogTickerHasASector() {
        #expect(NewsEvents.isLoaded)
        let missing = TickerCatalog.all.filter { NewsEvents.profile(for: $0.symbol, companyName: $0.name).sectorLabel == nil }.map(\.symbol)
        #expect(missing.isEmpty)
    }

    @Test func termsMatchWholeWordsOnly() {
        #expect(NewsEvents.hasTerm("amd unveils new chip", "amd"))
        #expect(!NewsEvents.hasTerm("islamdom news", "amd"))
        #expect(NewsEvents.hasTerm("nvidia ceo steps down", "nvidia ceo"))
        #expect(NewsEvents.hasTerm("s&p 500 closes higher", "s&p 500"))
        #expect(!NewsEvents.hasTerm("the dental plan", "ent"))
    }

    @Test func profileMergesCuratedSectorAndCatalogData() {
        let p = NewsEvents.profile(for: "NVDA", companyName: "NVIDIA Corporation")
        #expect(p.aliases.contains("nvidia") && p.people.contains("jensen huang"))
        #expect(["tsmc", "hbm", "euv"].allSatisfy(p.supply.contains))     // ticker-specific + semis sector
        #expect(p.competitors.contains("amd") && p.macro.contains("export controls"))
        #expect(p.sectorLabel == "Semiconductors")
        #expect(NewsEvents.profile(for: "CAT", companyName: "Caterpillar Inc.").aliases.contains("caterpillar"))
        #expect(!NewsEvents.profile(for: "GE", companyName: "General Electric Co.").aliases.contains("general"))
    }

    @Test func exposureChannels() {
        let nvda = NewsEvents.profile(for: "NVDA", companyName: "NVIDIA Corporation")
        func ex(_ h: String) -> NewsExposure? { NewsEvents.exposure(profile: nvda, headline: h) }
        #expect(ex("Nvidia unveils new AI chip")?.channel == "direct")
        #expect((ex("Nvidia unveils new AI chip")?.relevance ?? 0) >= 0.4)
        // Direct weight scales with relevance: tagged AND named counts in full, tag-only or mention-only less.
        func weight(_ h: String, _ symbols: [String] = []) -> Double? { NewsEvents.exposure(profile: nvda, headline: h, symbols: symbols)?.weight }
        #expect(weight("Nvidia posts record revenue", ["NVDA"]) == 1)
        #expect(abs((weight("Nvidia unveils new AI chip") ?? 0) - 0.4 / 0.8) < 1e-12)
        #expect(abs((weight("PwC spots a major shift in retirement money", ["NVDA", "AAPL", "MSFT"]) ?? 0) - 0.37 / 0.8) < 1e-12)
        // Surnames catch headlines that omit the first name.
        #expect(ex("What Huang's resignation means for chipmakers")?.channel == "people")
        #expect(ex("Jensen Huang has been ousted") == NewsExposure(channel: "people", relevance: 0.8, weight: 0.8, sign: 1))
        #expect(ex("TSMC warns of capacity shortage")?.channel == "supply" && ex("TSMC warns of capacity shortage")?.relevance == 0.5)
        #expect(ex("Chip stocks tumble as rates jump")?.channel == "sector")
        #expect(ex("US widens export controls on China")?.channel == "macro" && ex("US widens export controls on China")?.relevance == 0.25)
        #expect(ex("AMD wins huge cloud contract") == NewsExposure(channel: "competitor", relevance: 0.3, weight: 0.3, sign: -1))
        #expect(ex("Local bakery wins award") == nil)
        #expect(ex("TSMC export controls hit chip stocks")?.channel == "supply")   // strongest channel wins
        let dal = NewsEvents.profile(for: "DAL", companyName: "Delta Air Lines Inc.")
        let fuel = NewsEvents.exposure(profile: dal, headline: "Oil prices jump on supply fears")
        #expect(fuel?.channel == "macro" && fuel?.sign == -1)                      // inverse terms flip the sign
    }

    @Test func headlineTokensAndSameEvent() {
        func tokens(_ h: String, _ t: String = "NVDA", _ n: String = "NVIDIA Corporation") -> Set<String> {
            NewsEvents.headlineTokens(h, ignore: ignore(t, n))
        }
        func same(_ a: String, _ b: String, _ t: String = "NVDA", _ n: String = "NVIDIA Corporation") -> Bool {
            NewsEvents.sameEvent(tokens(a, t, n), tokens(b, t, n))
        }
        #expect(tokens("Nvidia stock jumps on record data center revenue - Reuters") == ["center", "data", "jump", "record", "revenue"])
        #expect(tokens("Tesla's 435,059 deliveries beat estimates", "TSLA", "Tesla, Inc.").contains("435059"))
        #expect(same("Tesla recalls 200,000 vehicles over safety defect - Reuters", "Tesla recalls over 200,000 vehicles due to safety defect - AP", "TSLA", "Tesla, Inc."))
        #expect(same("Nvidia CEO Jensen Huang steps down", "Jensen Huang steps down as Nvidia chief"))
        #expect(!same("Nvidia stock jumps on record data center revenue", "Nvidia stock falls after data center revenue misses"))
        #expect(!same("Nvidia unveils new gaming GPUs", "Nvidia faces antitrust probe in China"))
        #expect(!same("Nvidia earnings preview", "Nvidia earnings call transcript"))     // one shared generic word is not enough
        #expect(same("Apple bad news - Reuters", "Apple bad news - Bloomberg", "AAPL", "Apple Inc."))
    }

    @Test func coverageBoostIsSublinearAndCapped() {
        #expect(NewsEvents.coverageBoost(1) == 1)
        #expect(abs(NewsEvents.coverageBoost(2) - (1 + 0.5 * log(2.0))) < 1e-12)
        #expect(abs(NewsEvents.coverageBoost(10) - (1 + 0.5 * log(10.0))) < 1e-12)   // ~2.15: ten outlets != ten votes
        #expect(NewsEvents.coverageBoost(10_000) == 2.5)
    }

    @Test func groupsTheSameEventAcrossOutlets() {
        let tsla = ignore("TSLA", "Tesla, Inc.")
        let events = NewsEvents.groupEvents([
            item("Tesla recalls 200,000 vehicles over safety defect - Reuters", source: "Reuters", value: -0.6),
            item("Tesla recalls over 200,000 vehicles due to safety defect - AP", source: "AP", hours: 2, value: -0.8),
            item("Tesla recalls 200,000 vehicles safety defect - CNBC", source: "CNBC", hours: 3, value: -0.7),
            item("Tesla unveils new robotaxi", source: "Verge", hours: 5, value: 0.6),
        ], ignore: tsla)
        #expect(events.count == 2)
        let recall = events.first { $0.size == 3 }!
        #expect(recall.outlets == 3)
        #expect(abs(recall.value - (-0.6 - 0.8 - 0.7) / 3) < 1e-12)
        #expect(abs(recall.weight - (1 + 0.5 * log(3.0))) < 1e-12)
        #expect(recall.time == Self.t0.addingTimeInterval(-3 * 3600))      // event time = first report
    }

    @Test func sameOutletRepeatingCountsAsOneOutlet() {
        let events = NewsEvents.groupEvents([
            item("Nvidia ships record data center revenue", source: "Zacks"),
            item("Nvidia ships record data center revenue today", source: "Zacks", hours: 1),
        ], ignore: ignore("NVDA", "NVIDIA Corporation"))
        #expect(events.count == 1 && events[0].size == 2 && events[0].outlets == 1 && events[0].weight == 1)
    }

    @Test func doesNotMergeIdenticalHeadlinesMoreThan48HoursApart() {
        let events = NewsEvents.groupEvents([item("Nvidia supply update", hours: 0), item("Nvidia supply update", hours: 60)],
                                            ignore: ignore("NVDA", "NVIDIA Corporation"))
        #expect(events.count == 2)
    }

    @Test func indirectArticleKeepsItsOwnWeightAndSignInAMixedEvent() {
        let direct = item("Chip export curbs hit Nvidia hard", value: -0.6)
        let base = item("Chip export curbs hit hard - Bloomberg", source: "Bloomberg", value: 0.5)
        let indirect = ExposedArticle(article: base.article, exposure: NewsExposure(channel: "macro", relevance: 0.25, weight: 0.25, sign: 1),
                                      time: base.time, value: base.value)
        let events = NewsEvents.groupEvents([direct, indirect], ignore: ignore("NVDA", "NVIDIA Corporation"))
        #expect(events.count == 1 && events[0].size == 2 && events[0].channel == "direct")
        #expect(abs(events[0].value - (1 * -0.6 + 0.25 * 0.5) / 1.25) < 1e-12)
    }

    @Test func indirectQueriesAreOnePerChannelAndProxySafe() {
        let qs = NewsEvents.indirectQueries(NewsEvents.profile(for: "NVDA", companyName: "NVIDIA Corporation"))
        #expect(qs.count == 4)
        #expect(qs[0].contains("\"nvidia ceo\"") && qs[0].contains("\"jensen huang\""))
        #expect(qs.allSatisfy { $0.hasSuffix(" when:7d") })
    }

    @Test func weightedStats() {
        #expect(abs(Analytics.weightedMean([1, 0], [3, 1]) - 0.75) < 1e-12)
        #expect(Analytics.weightedStd([1, 1], [1, 1]) == 0)
        #expect(abs(Analytics.weightedMean([0.5, -0.2, 0.1, 0.8, -0.6], [1, 1, 1, 1, 1]) - 0.12) < 1e-12)
    }

    // MARK: storylines (mirrors the "storyline damping" tests in news.test.js)

    private static let now = Date(timeIntervalSince1970: 1_794_484_800)

    private func ev(_ i: Int, hoursAgo: Double, words: [String]) -> NewsEvent {
        let t = Self.now.addingTimeInterval(-hoursAgo * 3600)
        let a = Article(id: i, url: "u", headline: "h", summary: nil, body: nil, source: "X", publishedAt: t, sentimentLabel: nil, compound: nil,
                        relevanceScore: nil, sourceWeight: 1, nearEarnings: nil, isSecFiling: nil)
        return NewsEvent(id: i, articles: [a], outlets: 1, value: 0, weight: 1, time: t, latest: t, channel: "direct", relevance: 0.85, rep: a, tokens: Set(words))
    }
    /// 40 ordinary events over 20 days, each with its own distinctive words.
    private func ordinary(_ n: Int = 40) -> [NewsEvent] {
        (0..<n).map { ev($0, hoursAgo: 72 + Double($0) * 440 / Double(n), words: ["topic\($0)", "detail\($0)"]) }
    }
    /// A developing story: k events in the last 48h that all mention one word plus varied others.
    private func story(_ k: Int, word: String = "zorblax") -> [NewsEvent] {
        (0..<k).map { ev(1000 + $0, hoursAgo: 1 + Double($0) * 2, words: [word, "angle\($0)", "view\($0)"]) }
    }

    @Test func dampsTheKthEventOfABurstingTermByInverseSqrtRank() {
        let out = NewsEvents.dampStorylines(ordinary() + story(20))
        let s = out.filter { $0.storyline == "zorblax" }.sorted { $0.storyRank < $1.storyRank }
        #expect(s.count == 20)
        #expect(s.map(\.storyRank) == Array(1...20))                      // earliest first
        #expect(s[0].damp == 1)
        #expect(abs(s[3].damp - 0.5) < 1e-12)                              // 4th: 1/sqrt(4)
        #expect(abs(s[15].damp - 0.25) < 1e-12)                            // 16th: 1/4, at the floor
        #expect(s[19].damp == 0.25)                                        // never below the floor
        #expect(s.allSatisfy { abs($0.weight - $0.damp) < 1e-12 })         // weight starts at 1
    }

    @Test func leavesUnrelatedEventsAlone() {
        let out = NewsEvents.dampStorylines(ordinary() + story(20))
        #expect(out.filter { $0.storyline == nil }.allSatisfy { $0.damp == 1 && $0.weight == 1 })
    }

    @Test func neverTreatsExcludedVocabularyAsAStoryline() {
        let out = NewsEvents.dampStorylines(ordinary() + story(20), exclude: ["zorblax"])
        #expect(out.allSatisfy { $0.storyline == nil && $0.damp == 1 })
    }

    @Test func needsContextAndLeavesFewEventsUntouched() {
        let few = story(12)
        #expect(NewsEvents.dampStorylines(few).allSatisfy { $0.storyline == nil && $0.damp == 1 })
    }

    @Test func steadyVocabularyIsNotABurstWhenOlderEventsProvideABaseline() {
        let steady = (0..<60).map { ev($0, hoursAgo: 6 + Double($0) * 11, words: $0 % 3 == 0 ? ["regular", "x\($0)"] : ["y\($0)", "z\($0)"]) }
        #expect(NewsEvents.dampStorylines(steady).allSatisfy { $0.storyline == nil })
    }

    @Test func withNoBaselineItNeedsMoreEventsAndAHigherShare() {
        let base = (0..<50).map { ev($0, hoursAgo: 1 + Double($0) * 0.9, words: ["t\($0)", "u\($0)"]) }
        var small = base; for i in 0..<5 { small[i] = ev(i, hoursAgo: 1 + Double(i) * 0.9, words: ["minorword", "a\(i)"]) }   // 5 events (10%)
        #expect(NewsEvents.dampStorylines(small).allSatisfy { $0.storyline == nil })
        var big = base; for i in 0..<12 { big[i] = ev(i, hoursAgo: 1 + Double(i) * 0.9, words: ["majorword", "a\(i)"]) }       // 12 events (24%)
        #expect(NewsEvents.dampStorylines(big).filter { $0.storyline == "majorword" }.count == 12)
    }

    @Test func onlyEventsWithin72HoursPileUp() {
        let long = (0..<24).map { ev(3000 + $0, hoursAgo: 2 + Double($0) * 6, words: ["zorblax", "a\($0)", "b\($0)"]) }
        let out = NewsEvents.dampStorylines(ordinary(60) + long).filter { $0.storyline == "zorblax" }
        #expect(out.count >= 20)
        #expect((out.map(\.storyRank).max() ?? 0) <= 13 && (out.map(\.storyRank).max() ?? 0) >= 10)   // 72h / 6h = 12 earlier events + itself
        #expect(out.allSatisfy { $0.damp >= 0.25 })
    }

    @Test func storylineExclusions() {
        let nvda = NewsEvents.storylineExclusions(NewsEvents.profile(for: "NVDA", companyName: "NVIDIA Corporation"))
        #expect(nvda.contains("ai"))            // ubiquitous headline word
        #expect(nvda.contains("tsmc"))          // NVDA's own topical vocabulary
        #expect(!nvda.contains("huang"))        // a leadership story must stay detectable
        let tsla = NewsEvents.storylineExclusions(NewsEvents.profile(for: "TSLA", companyName: "Tesla, Inc."))
        #expect(tsla.contains("musk"))          // chronic: Musk is in nearly every Tesla story
        #expect(!tsla.contains("spacex"))       // but a Tesla-SpaceX merger story is detectable
    }

    @Test func corporateSuffixesAndExchangeTagsAreNotInformative() {
        #expect(!NewsEvents.headlineTokens("JPMorgan Chase & Co. (NYSE:JPM) Shares Down 1.9%").contains("co"))
        #expect(!NewsEvents.headlineTokens("Acme Corp Inc Ltd NYSE Nasdaq results").contains("corp"))
    }
}

