import Foundation
import Testing
@testable import NewsEdge

/// Same scenarios and expectations as the "semantic storylines" block in frontend/src/lib/local/semantic.test.js.
struct SemanticStorylineTests {
    private static let now = Date(timeIntervalSince1970: 1_794_484_800)
    private let window = NewsEvents.storyWindow
    private let dim = 64

    private func basis(_ k: Int, _ extra: [(Int, Float)] = []) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        v[k] = 1
        for (j, x) in extra { v[j] = x }
        return v
    }
    private func words(_ headline: String) -> Set<String> { Set(headline.lowercased().split(separator: " ").map(String.init)) }
    private func ev(_ i: Int, _ hoursAgo: Double, _ headline: String, _ vec: [Float]) -> NewsEvent {
        let t = Self.now.addingTimeInterval(-hoursAgo * 3600)
        let a = Article(id: i, url: "u\(i)", headline: headline, summary: nil, body: nil, source: "s\(i)", publishedAt: t, sentimentLabel: nil, compound: nil,
                        relevanceScore: nil, sourceWeight: 1, nearEarnings: nil, isSecFiling: nil, emb: EmbeddingCodec.quantize(vec))
        return NewsEvent(id: i, articles: [a], outlets: 1, value: 0, weight: 1, time: t, latest: t, channel: "direct", relevance: 0.9, rep: a, tokens: words(headline))
    }
    private func ordinary() -> [NewsEvent] { (0..<40).map { ev($0, 96 + Double($0) * 12, "alpha\($0) beta\($0)", basis($0)) } }
    private func story(_ k: Int = 12, _ headline: (Int) -> String = { "gamma\($0) delta\($0)" }) -> [NewsEvent] {
        (0..<k).map { ev(100 + $0, 1 + 4 * Double($0), headline($0), basis(50, [(51 + $0 % 10, 0.05 * Float($0 + 1))])) }
    }

    @Test func eventVectorIsTheUnitMeanOfItsMembersNilWithoutEmbeddings() {
        var e = ev(1, 0, "x", [1, 0]); let b = ev(2, 0, "y", [0, 1])
        e = NewsEvent(id: 1, articles: e.articles + b.articles, outlets: 2, value: 0, weight: 1, time: e.time, latest: e.time, channel: "direct", relevance: 1, rep: e.rep, tokens: [])
        let v = NewsSemantic.eventVector(e)!
        #expect(abs(v.reduce(0) { $0 + $1 * $1 } - 1) < 1e-4 && abs(v[0] - v[1]) < 0.02)
        #expect(NewsSemantic.eventVector(ev(3, 0, "z", [1, 0]).withoutEmbeddings()) == nil)
    }

    @Test func findsAStorylineWhoseEventsShareNoWordsRankingEarliestFirst() {
        let events = ordinary() + story()
        let found = NewsSemantic.storylines(events, window: window)
        #expect(found[40...].compactMap { $0?.rank }.sorted() == Array(1...12))
        #expect(found[..<40].allSatisfy { $0 == nil })
    }

    @Test func needsContextAndABurst() {
        #expect(NewsSemantic.storylines(story(), window: window).allSatisfy { $0 == nil })
        let steady = (0..<60).map { ev($0, 6 + Double($0) * 11, "w\($0) x\($0)", $0 % 3 == 0 ? basis(50, [(51 + $0 % 10, 0.05)]) : basis($0)) }
        #expect(NewsSemantic.storylines(steady, window: window).allSatisfy { $0 == nil })
    }

    @Test func doesNotTieTwoDifferentPeopleWithTheSameSurname() {
        let jensen = (0..<4).map { ev(200 + $0, 1 + 3 * Double($0), "Chip chief Jensen Huang resigns \($0)", basis(50, [(51, 0.1 * Float($0))])) }
        let alice = (0..<4).map { ev(300 + $0, 2 + 3 * Double($0), "Rival hires Alice Huang as chief \($0)", basis(52, [(50, 0.7 + 0.05 * Float($0))])) }
        let events = ordinary() + jensen + alice
        #expect(NewsSemantic.storylines(events, window: window, similarity: 0.5, noEntityCosine: 0.7)[40]?.local == 4)
        #expect(NewsSemantic.storylines(events, window: window, similarity: 0.5, noEntityCosine: 0)[40]?.local == 8)
    }

    @Test func shadowOnlyLogsOnDampsByInverseSqrtRankOffDoesNothing() {
        var log: [NewsSemantic.StoryDecision] = []
        let shadow = NewsEvents.dampStorylines(ordinary() + story(), mode: "shadow") { log.append($0) }
        #expect(shadow.allSatisfy { $0.damp == 1 && $0.storyline == nil })
        #expect(!log.isEmpty && log[0].applied == false && log[0].mode == "shadow")
        #expect(NewsEvents.dampStorylines(ordinary() + story(), mode: "off").allSatisfy { $0.damp == 1 })
        let on = NewsEvents.dampStorylines(ordinary() + story(), mode: "on")
        let s = on.filter { $0.storyKind == "semantic" }.sorted { $0.storyRank < $1.storyRank }
        #expect(s.map(\.storyRank) == Array(2...12))               // the first piece is never damped
        #expect(abs(s[2].damp - 0.5) < 1e-12)                       // 4th piece
        #expect(s.allSatisfy { abs($0.weight - $0.damp) < 1e-12 })
        #expect(on.filter { $0.storyKind != "semantic" }.allSatisfy { $0.damp == 1 })
    }

    @Test func neverDampsLessThanTheWordBasedStorylineAlreadyDoes() {
        var log: [NewsSemantic.StoryDecision] = []
        let out = NewsEvents.dampStorylines(ordinary() + story(12) { "zorblax gamma\($0) delta\($0)" }, mode: "on") { log.append($0) }
        let token = out.filter { $0.storyline == "zorblax" }
        #expect(token.count == 12 && token.allSatisfy { $0.storyKind == nil } && log.isEmpty)
    }

    @Test func configShipsStorylineDefaults() {
        let s = NewsConfig.shared.storylines.semantic
        #expect(s.similarity == 0.55 && s.noSharedEntityCosine == 0.75)
    }
}

private extension NewsEvent {
    func withoutEmbeddings() -> NewsEvent {
        var stripped = articles
        for i in stripped.indices { stripped[i].emb = nil }
        return NewsEvent(id: id, articles: stripped, outlets: outlets, value: value, weight: weight, time: time, latest: latest, channel: channel, relevance: relevance, rep: rep, tokens: tokens)
    }
}
