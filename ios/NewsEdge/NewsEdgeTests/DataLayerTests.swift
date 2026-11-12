import Foundation
import Testing
@testable import NewsEdge

// MARK: - URLProtocol stub (global, so suites using it run serialized)

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [String: () throws -> (Int, Data)] = [:]
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static let lock = NSLock()

    static func norm(_ key: String) -> String { key.hasSuffix("/") ? String(key.dropLast()) : key }
    static func reset() { lock.lock(); routes = [:]; hits = [:]; lock.unlock() }
    static func route(_ hostPath: String, status: Int = 200, body: String) {
        lock.lock(); routes[norm(hostPath)] = { (status, Data(body.utf8)) }; lock.unlock()
    }
    static func fail(_ hostPath: String) {
        lock.lock(); routes[norm(hostPath)] = { throw URLError(.notConnectedToInternet) }; lock.unlock()
    }
    static func hitCount(_ hostPath: String) -> Int { lock.lock(); defer { lock.unlock() }; return hits[norm(hostPath)] ?? 0 }
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let key = Self.norm((request.url?.host ?? "") + (request.url?.path ?? ""))
        Self.lock.lock(); Self.hits[key, default: 0] += 1; let route = Self.routes[key]; Self.lock.unlock()
        do {
            guard let route else { throw URLError(.notConnectedToInternet) }
            let (status, data) = try route()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// Counts calls to the injected scorer (a stand-in for FinBERT).
final class ScoreLog: @unchecked Sendable {
    private let lock = NSLock()
    private var headlines: [String] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return headlines.count }
    func score(_ h: String) -> Double {
        lock.lock(); headlines.append(h); lock.unlock()
        return h.contains("good") ? 0.8 : h.contains("bad") ? -0.6 : 0
    }
}

private let yahooChart = "query1.finance.yahoo.com/v8/finance/chart/AAPL"
private let yahooSearch = "query1.finance.yahoo.com/v1/finance/search"
private let nasdaq = "api.nasdaq.com/api/quote/AAPL/historical"
private let googleRSS = "news.google.com/rss/search"

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func chartJSON(_ closes: String, stamps: String) -> String {
    #"{"chart":{"result":[{"timestamp":[\#(stamps)],"indicators":{"quote":[{"open":[\#(closes)],"high":[\#(closes)],"low":[\#(closes)],"close":[\#(closes)],"volume":[10,20,30]}]}}]}}"#
}

private struct NewsItem {
    var title: String, publisher: String = "Zacks", time: Date, tickers: [String] = ["AAPL"]
}

private func searchJSON(_ items: [NewsItem], extraRaw: String? = nil) -> String {
    let rows = items.map { i in
        #"{"uuid":"\#(i.title)|\#(i.publisher)","title":"\#(i.title)","publisher":"\#(i.publisher)","link":"https://x.test/\#(abs(i.title.hashValue))","providerPublishTime":\#(Int(i.time.timeIntervalSince1970)),"relatedTickers":[\#(i.tickers.map { "\"\($0)\"" }.joined(separator: ","))]}"#
    }
    return #"{"news":[\#((rows + (extraRaw.map { [$0] } ?? [])).joined(separator: ","))]}"#
}

private let nasdaqJSON = #"""
{"data":{"tradesTable":{"rows":[
{"date":"11/11/2026","close":"$355.63","volume":"34,453,480","open":"$349.545","high":"$355.91","low":"$349.325"},
{"date":"11/10/2026","close":"$348.51","volume":"29,756,060","open":"$351.35","high":"$353.87","low":"$346.4605"},
{"date":"11/09/2026","close":"N/A","volume":"1","open":"$1","high":"$1","low":"$1"}
]}}}
"""#

private let rss = """
<?xml version="1.0"?><rss><channel>
<item><title>Apple unveils new chip - The Verge</title><link>https://g.test/1</link><pubDate>Mon, 09 Nov 2026 10:00:00 GMT</pubDate><source url="x">The Verge</source></item>
<item><title><![CDATA[AAPL shares climb on services growth - Reuters]]></title><link>https://g.test/2</link><pubDate>Tue, 10 Nov 2026 10:00:00 GMT</pubDate><source url="x">Reuters</source></item>
<item><title>Oil prices slide again - Bloomberg</title><link>https://g.test/3</link><pubDate>Tue, 10 Nov 2026 12:00:00 GMT</pubDate><source url="x">Bloomberg</source></item>
</channel></rss>
"""

// MARK: - Pure parsing

struct ParsingTests {
    @Test func nasdaqParsesAndReversesToOldestFirst() {
        let bars = YahooClient.parseNasdaq(Data(nasdaqJSON.utf8))
        #expect(bars.count == 2)   // the row with an unparsable price is skipped
        #expect(bars[0].close == 348.51 && bars[0].volume == 29_756_060 && bars[0].open == 351.35)
        #expect(bars[1].close == 355.63)
        #expect(bars[0].timestamp < bars[1].timestamp)
        #expect(YahooClient.parseNasdaq(Data("<html>blocked</html>".utf8)).isEmpty)
        #expect(YahooClient.parseNasdaq(Data(#"{"data":{"tradesTable":null}}"#.utf8)).isEmpty)
    }

    @Test func googleRSSMapping() {
        let items = GoogleNewsClient.articles(from: Data(rss.utf8), ticker: "AAPL", companyName: "Apple Inc.", limit: 30)
        #expect(items.count == 3)
        #expect(items.map(\.headline) == ["Oil prices slide again", "AAPL shares climb on services growth", "Apple unveils new chip"])
        #expect(items.map(\.source) == ["Bloomberg", "Reuters", "The Verge"])
        // Only headlines mentioning the ticker or the company's first name are tagged relevant.
        #expect(items.map { $0.symbols ?? [] } == [[], ["AAPL"], ["AAPL"]])
        #expect(GoogleNewsClient.articles(from: Data(rss.utf8), ticker: "AAPL", companyName: nil, limit: 1).count == 1)
    }

    @Test func symbolNormalization() {
        #expect(Analytics.yahooSymbol("brk.b") == "BRK-B")
        #expect(Analytics.relevance(ticker: "BRK.B", headline: "Berkshire results", symbols: ["BRK-B"]) == 0.45)
    }
}

// MARK: - YahooClient / NewsStore / APIClient with stubbed network

@Suite(.serialized)
struct DataLayerTests {
    init() { StubProtocol.reset() }

    private func yahoo(dir: URL = tempDir()) -> YahooClient {
        YahooClient(session: StubProtocol.session, barsDirectory: dir)
    }

    @Test func yahooBarsSkipNullsAndDecode() async throws {
        StubProtocol.route(yahooChart, body: chartJSON("1.0,null,3.0", stamps: "1767225600,1767312000,1767398400"))
        let bars = try await yahoo().bars(ticker: "AAPL")
        #expect(bars.map(\.close) == [1.0, 3.0])
        #expect(bars[0].timestamp == Date(timeIntervalSince1970: 1_767_225_600))
        #expect(bars[0].volume == 10 && bars[1].volume == 30)
    }

    @Test func barsFallBackToNasdaqThenDiskThenThrow() async throws {
        let dir = tempDir()
        StubProtocol.route(yahooChart, status: 500, body: "")
        StubProtocol.route(nasdaq, body: nasdaqJSON)
        let viaNasdaq = try await yahoo(dir: dir).bars(ticker: "AAPL")
        #expect(viaNasdaq.map(\.close) == [348.51, 355.63])

        // Everything down: the bars saved above come back from disk.
        StubProtocol.fail(yahooChart); StubProtocol.fail(nasdaq)
        let cached = try await yahoo(dir: dir).bars(ticker: "AAPL")
        #expect(cached.map(\.close) == [348.51, 355.63])

        // Nothing cached and everything down: the failure surfaces.
        await #expect(throws: APIError.self) { try await yahoo(dir: tempDir()).bars(ticker: "AAPL") }
    }

    @Test func unknownSymbolYieldsEmptyBarsNotAnError() async throws {
        // Yahoo answers 404 for symbols it doesn't know; Nasdaq answers with no rows.
        StubProtocol.route(yahooChart, status: 404, body: #"{"chart":{"result":null,"error":{"code":"Not Found"}}}"#)
        StubProtocol.route(nasdaq, body: #"{"data":{"tradesTable":{"rows":[]}}}"#)
        #expect(try await yahoo().bars(ticker: "AAPL").isEmpty)
    }

    @Test func newsMappingDropsIncompleteItems() async throws {
        let now = Date()
        StubProtocol.route(yahooSearch, body: searchJSON([NewsItem(title: "AAPL good", time: now)], extraRaw: #"{"uuid":"x","publisher":"p"}"#))
        let items = try await yahoo().news(ticker: "AAPL")
        #expect(items.count == 1 && items[0].headline == "AAPL good" && items[0].symbols == ["AAPL"])
        #expect(items[0].compound == nil) // scoring is the store's job
    }

    @Test func storeScoresOnlyNewArticlesAndMerges() async throws {
        let log = ScoreLog(), now = Date()
        StubProtocol.route(yahooSearch, body: searchJSON([NewsItem(title: "AAPL good one", time: now)]))
        StubProtocol.fail(googleRSS)
        let store = NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                              score: log.score, companyName: { _ in "Apple Inc." })

        let first = try await store.articles(ticker: "AAPL")
        #expect(first.count == 1 && first[0].compound == 0.8 && first[0].sentimentLabel == "POSITIVE")
        #expect(log.count == 1)

        // A later fetch returns the old item plus a new one: only the new one is scored.
        StubProtocol.route(yahooSearch, body: searchJSON([
            NewsItem(title: "AAPL good one", time: now), NewsItem(title: "AAPL bad two", time: now.addingTimeInterval(60)),
        ]))
        let second = try await NewsStore(directory: store.directoryForTests, yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                                         score: log.score, companyName: { _ in nil }).articles(ticker: "AAPL")
        #expect(second.map(\.headline) == ["AAPL bad two", "AAPL good one"]) // newest first
        #expect(log.count == 2)
    }

    @Test func storePrunesOldArticlesAndBackfillsOnce() async throws {
        let log = ScoreLog(), now = Date()
        StubProtocol.route(yahooSearch, body: searchJSON([
            NewsItem(title: "AAPL good fresh", time: now), NewsItem(title: "AAPL good ancient", time: now.addingTimeInterval(-100 * 86_400)),
        ]))
        StubProtocol.route(googleRSS, body: "<rss><channel></channel></rss>")
        let dir = tempDir()
        func makeStore() -> NewsStore {
            NewsStore(directory: dir, yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session), score: log.score, companyName: { _ in nil })
        }
        let result = try await makeStore().articles(ticker: "AAPL")
        #expect(result.map(\.headline) == ["AAPL good fresh"])  // >90 days is pruned
        #expect(StubProtocol.hitCount(googleRSS) == 4)           // one request per weekly window
        _ = try await makeStore().articles(ticker: "AAPL")       // cache exists now, so no second backfill
        #expect(StubProtocol.hitCount(googleRSS) == 4)
    }

    @Test func storeBackfillsFromGoogleAndServesCacheOffline() async throws {
        let log = ScoreLog(), dir = tempDir()
        StubProtocol.route(yahooSearch, body: #"{"news":[]}"#)
        StubProtocol.route(googleRSS, body: rss.replacingOccurrences(of: "2026", with: String(Calendar.current.component(.year, from: Date()))))
        func makeStore(_ y: YahooClient) -> NewsStore {
            NewsStore(directory: dir, yahoo: y, google: GoogleNewsClient(session: StubProtocol.session), score: log.score, companyName: { _ in "Apple Inc." })
        }
        let filled = try await makeStore(yahoo()).articles(ticker: "AAPL")
        #expect(filled.count == 3)

        StubProtocol.fail(yahooSearch)
        #expect(try await makeStore(yahoo()).articles(ticker: "AAPL").count == 3) // offline: cache

        // Offline with no cache and no backfill source: error.
        StubProtocol.fail(googleRSS)
        await #expect(throws: APIError.self) {
            try await NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                                score: log.score, companyName: { _ in nil }).articles(ticker: "AAPL")
        }
    }

    @Test func apiClientFiltersDedupsAndAggregates() async throws {
        // Yesterday 12:00 UTC, so a/b/d share a UTC day regardless of when the test runs.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.startOfDay(for: Date()).addingTimeInterval(-12 * 3600)
        StubProtocol.route(yahooSearch, body: searchJSON([
            NewsItem(title: "AAPL good earnings", time: base),
            NewsItem(title: "Apple bad news - Reuters", publisher: "Reuters", time: base.addingTimeInterval(-3600)),
            NewsItem(title: "Apple bad news - Bloomberg", publisher: "Bloomberg", time: base.addingTimeInterval(-7200)), // dup of b
            NewsItem(title: "Market roundup", time: base.addingTimeInterval(-3600 * 2), // 8 tags -> relevance 0.20
                     tickers: ["AAPL", "MSFT", "NVDA", "TSLA", "AMZN", "GOOG", "META", "NFLX"]),
            NewsItem(title: "AAPL good old", time: base.addingTimeInterval(-10 * 86_400)),
        ]))
        StubProtocol.fail(googleRSS)
        let log = ScoreLog()
        let store = NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                              score: log.score, companyName: { _ in nil })
        let api = APIClient(yahoo: yahoo(), store: store)

        let week = try await api.articles(ticker: "AAPL", days: 7)
        #expect(week.map(\.headline) == ["AAPL good earnings", "Apple bad news - Reuters"]) // dup + low relevance dropped
        #expect(week[0].relevanceScore == 0.85 && week[1].relevanceScore == 0.45)
        #expect(try await api.articles(ticker: "AAPL", days: 30).count == 3)               // adds the 10-day-old one
        #expect(try await api.articles(ticker: "AAPL", days: 7, minRelevance: 0.2).count == 3) // roundup passes at 0.2
        #expect(try await api.articles(ticker: "AAPL", days: 7, limit: 1).count == 1)

        // Weighted: good 0.8x1.0, bad -0.6x1.25 = -0.75. EWMA runs oldest to newest: -0.75 then 0.8.
        let summary = try await api.sentimentSummary(ticker: "AAPL", days: 7)
        #expect(summary.count == 2)
        #expect(summary.labelDistribution == ["POSITIVE": 1, "NEUTRAL": 0, "NEGATIVE": 1])
        #expect(abs(summary.meanCompound - 0.025) < 1e-9)
        #expect(abs(summary.ewmaCompound - (-0.285)) < 1e-9)

        let trend = try await api.sentimentTrend(ticker: "AAPL", hours: 24 * 30)
        #expect(trend.points.map(\.articleCount) == [1, 2])   // the old day, then yesterday
        #expect(trend.points.last?.bucket == utc.startOfDay(for: base))
        #expect(abs((trend.points.last?.meanCompound ?? 0) - 0.025) < 1e-9)
    }

    @Test func apiClientRisk() async throws {
        let closes = (0..<40).map { String(100 + $0) }.joined(separator: ",")
        let stamps = (0..<40).map { String(1_767_225_600 + $0 * 86_400) }.joined(separator: ",")
        let json = #"{"chart":{"result":[{"timestamp":[\#(stamps)],"indicators":{"quote":[{"open":[\#(closes)],"high":[\#(closes)],"low":[\#(closes)],"close":[\#(closes)],"volume":[\#((0..<40).map { _ in "1" }.joined(separator: ","))]}]}}]}}"#
        StubProtocol.route(yahooChart, body: json)
        StubProtocol.route("query1.finance.yahoo.com/v8/finance/chart/SPY", body: json)
        let risk = try await APIClient(yahoo: yahoo(), store: NewsStore(directory: tempDir(), yahoo: yahoo())).riskMetrics(ticker: "AAPL")
        #expect(abs(risk.betaToBenchmark - 1) < 1e-9)   // identical series
        #expect(risk.maxDrawdown == 0 && risk.highWaterMark == 139)
    }
}

extension NewsStore {
    /// Tests reopen a store on the same directory to simulate a relaunch.
    nonisolated var directoryForTests: URL { _directoryForTests }
}
