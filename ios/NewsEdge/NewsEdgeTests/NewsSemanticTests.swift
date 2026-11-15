import Foundation
import Testing
@testable import NewsEdge

/// Same scenarios and expectations as frontend/src/lib/local/semantic.test.js: the two implementations must agree.
struct NewsSemanticTests {
    private static let t0 = Date(timeIntervalSince1970: 1_794_484_800)
    private let window: TimeInterval = 48 * 3600

    private func unit(_ v: Float...) -> [Float] {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return v.map { $0 / n }
    }
    /// An item as groupEvents/merges see it; `vec` goes through the real int8 codec.
    private func item(_ id: Int, _ headline: String, _ hours: Double, _ vec: [Float]?) -> ExposedArticle {
        let article = Article(id: id, url: "u\(id)", headline: headline, summary: nil, body: nil, source: "src\(id)",
                              publishedAt: Self.t0.addingTimeInterval(hours * 3600), sentimentLabel: nil, compound: nil,
                              relevanceScore: nil, sourceWeight: 1, nearEarnings: nil, isSecFiling: nil,
                              emb: vec.map(EmbeddingCodec.quantize))
        return ExposedArticle(article: article, exposure: NewsExposure(channel: "direct", relevance: 0.9, weight: 1, sign: 1),
                              time: article.publishedAt, value: 0.1)
    }
    private func run(_ items: [ExposedArticle], groups: [[Int]]? = nil, threshold: Double = 0.8, log: ((NewsSemantic.Decision) -> Void)? = nil) -> [NewsSemantic.Merge] {
        NewsSemantic.merges(items: items, groups: groups ?? items.indices.map { [$0] }, window: window, threshold: threshold, log: log)
    }

    @Test func timeSimilarityInterpolatesAndIsZeroBeyondTheWindow() {
        #expect(NewsSemantic.timeSimilarity(0) == 1)
        #expect(abs(NewsSemantic.timeSimilarity(12 * 3600) - 0.875) < 1e-9)
        #expect(abs(NewsSemantic.timeSimilarity(24 * 3600) - 0.75) < 1e-9)
        #expect(abs(NewsSemantic.timeSimilarity(36 * 3600) - 0.5) < 1e-9)
        #expect(abs(NewsSemantic.timeSimilarity(-48 * 3600) - 0.25) < 1e-9)
        #expect(NewsSemantic.timeSimilarity(49 * 3600) == 0)
    }

    @Test func entitiesNormaliseAmountsAndPercentages() {
        #expect(NewsSemantic.entities(of: "Pfizer gets $1.5 billion from Blackstone").contains("#1500000000"))
        #expect(NewsSemantic.entities(of: "Pfizer secures up to $1.5B funding").contains("#1500000000"))
        #expect(NewsSemantic.entities(of: "Boeing to cut 5% of workforce").contains("5%"))
        #expect(NewsSemantic.entities(of: "Tesla recalls 200,000 vehicles").contains("#200000"))
        #expect(NewsSemantic.entities(of: "Stock rises over 3 days").isEmpty) // bare small numbers are not facts
    }

    @Test func entitiesFindCuratedTermsAndMidHeadlineNamesButNotTheCompanyOrGenericRoles() {
        let e = NewsSemantic.entities(of: "Apple supplier Foxconn faces probe as Tim Cook visits India", terms: ["foxconn"], ignore: ["apple"])
        #expect(e.contains("foxconn") && e.contains("tim cook") && e.contains("india") && !e.contains("apple"))
        #expect(!NewsSemantic.entities(of: "Company says CEO Smith to retire").contains("ceo"))
    }

    @Test func titleCaseHeadlinesYieldNoCapitalisedEntities() {
        #expect(NewsSemantic.entities(of: "Chipmaker Chief Executive Steps Down After A Decade At The Helm").isEmpty)
    }

    @Test func entitySimilarityAndPairScoreWeights() {
        #expect(NewsSemantic.entitySimilarity(["a", "b"], ["a", "b", "c"]) == 1)
        #expect(NewsSemantic.entitySimilarity(["a", "b"], ["c"]) == 0)
        #expect(NewsSemantic.entitySimilarity([], ["a"]) == nil)
        #expect(abs(NewsSemantic.pairScore(cosine: 0.8, entity: 1, dt: 0) - (0.65 * 0.8 + 0.2 + 0.15)) < 1e-9)
        #expect(abs(NewsSemantic.pairScore(cosine: 0.8, entity: nil, dt: 0) - (0.65 * 0.8 + 0.15) / 0.8) < 1e-9)
    }

    @Test func mergesGroupsOfNearIdenticalMeaningCloseInTime() {
        let items = [item(1, "Chipmaker chief steps down", 0, unit(1, 0.05, 0)), item(2, "Nvidia CEO resigns", 2, unit(1, 0.08, 0))]
        let merges = run(items)
        #expect(merges.count == 1 && merges[0].members.sorted() == [0, 1] && merges[0].score > 0.8)
    }

    @Test func doesNotMergeDifferentMeaningsOrTheSameMeaningOutsideTheWindow() {
        #expect(run([item(1, "a", 0, unit(1, 0, 0)), item(2, "b", 1, unit(0, 1, 0))]).isEmpty)
        #expect(run([item(1, "a", 0, unit(1, 0, 0)), item(2, "b", 72, unit(1, 0, 0))]).isEmpty)
    }

    @Test func averageLinkageDoesNotChainAThroughBToC() {
        let items = [item(1, "a", 0, unit(1, 0, 0)), item(2, "b", 0, unit(1, 0.45, 0)), item(3, "c", 0, unit(1, 0.9, 0))]
        let merges = run(items, threshold: 0.88)
        #expect(merges.count <= 1 && merges.allSatisfy { $0.members.count == 2 })
    }

    @Test func skipsArticlesWithoutEmbeddingsAndNeverPairsMembersOfOneLexicalGroup() {
        #expect(run([item(1, "a", 0, unit(1, 0, 0)), item(2, "b", 0, nil)]).isEmpty)
        #expect(run([item(1, "a", 0, unit(1, 0, 0)), item(2, "b", 0, unit(1, 0, 0))], groups: [[0, 1]]).isEmpty)
    }

    @Test func logsMergesAndNearMissesWithTheNumbersBehindThem() {
        var log: [NewsSemantic.Decision] = []
        _ = run([item(1, "x", 0, unit(1, 0, 0)), item(2, "y", 0, unit(1, 0.01, 0)), item(3, "z", 0, unit(1, 0.5, 0))], threshold: 0.95) { log.append($0) }
        let merge = log.first { $0.kind == .merge }
        #expect(merge != nil && merge?.dtHours == 0 && merge?.cosine ?? 0 > 0.9)
        #expect(log.contains { $0.kind == .nearMiss })
    }

    // MARK: - groupEvents with the semantic stage

    private func triple() -> [ExposedArticle] {
        [item(1, "Quarterly results beat forecasts", 0, unit(1, 0.02, 0)),
         item(2, "Zorblax earnings top expectations", 3, unit(1, 0.05, 0)),      // no shared words: only the embedding links them
         item(3, "Quarterly results beat forecasts again", 1, unit(1, 0.03, 0))] // lexically the same story as #1
    }
    private let xyz = NewsEvents.profile(for: "XYZ", companyName: "XYZ Inc.")

    @Test func offAndShadowLeaveGroupingToTheLexicalRulesButShadowStillLogs() {
        var log: [NewsSemantic.Decision] = []
        #expect(NewsEvents.groupEvents(triple(), ignore: [], profile: xyz, mode: "off", threshold: 0.8).count == 2)
        let shadow = NewsEvents.groupEvents(triple(), ignore: [], profile: xyz, mode: "shadow", threshold: 0.8) { log.append($0) }
        #expect(shadow.count == 2 && shadow.allSatisfy { $0.semantic == nil })
        #expect(log.first { $0.kind == .merge }?.applied == false)
    }

    @Test func onAddsTheSemanticLinkWithoutUndoingTheLexicalOneAndRecordsTheScore() {
        var log: [NewsSemantic.Decision] = []
        let events = NewsEvents.groupEvents(triple(), ignore: [], profile: xyz, mode: "on", threshold: 0.8) { log.append($0) }
        #expect(events.count == 1 && events[0].size == 3 && (events[0].semantic ?? 0) > 0.8)
        #expect(log.first { $0.kind == .merge }?.applied == true)
    }

    @Test func articlesWithoutEmbeddingsGroupExactlyAsBeforeInEveryMode() {
        let plain = triple().map { x -> ExposedArticle in var a = x.article; a.emb = nil; return ExposedArticle(article: a, exposure: x.exposure, time: x.time, value: x.value) }
        for mode in ["off", "shadow", "on"] { #expect(NewsEvents.groupEvents(plain, ignore: [], profile: xyz, mode: mode, threshold: 0.8).count == 2) }
    }

    @Test func configShipsOnAtPointNine() {
        let s = NewsConfig.shared.events.semantic
        #expect(s.mode == "on" && s.threshold == 0.9 && s.weights.semantic == 0.65 && s.timeSimilarity.count == 3)
    }
}
