import CryptoKit
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

    @Test func malformedChartWithShortArraysSkipsCandlesInsteadOfCrashing() async throws {
        // 3 timestamps but only 2 closes/opens/highs/lows and 1 volume: the third candle is skipped, not an index crash.
        StubProtocol.route(yahooChart, body: #"{"chart":{"result":[{"timestamp":[1,2,3],"indicators":{"quote":[{"open":[1,2],"high":[1,2],"low":[1,2],"close":[1,2],"volume":[5]}]}}]}}"#)
        let bars = try await yahoo().bars(ticker: "AAPL")
        #expect(bars.map(\.close) == [1, 2])
        #expect(bars.map(\.volume) == [5, 0])
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
                              score: log.score, companyName: { _ in "Apple Inc." }, indirect: false)

        let first = try await store.articles(ticker: "AAPL")
        #expect(first.count == 1 && first[0].compound == 0.8 && first[0].sentimentLabel == "POSITIVE")
        #expect(log.count == 1)

        // A later fetch returns the old item plus a new one: only the new one is scored.
        StubProtocol.route(yahooSearch, body: searchJSON([
            NewsItem(title: "AAPL good one", time: now), NewsItem(title: "AAPL bad two", time: now.addingTimeInterval(60)),
        ]))
        let second = try await NewsStore(directory: store.directoryForTests, yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                                         score: log.score, companyName: { _ in nil }, indirect: false).articles(ticker: "AAPL")
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
            NewsStore(directory: dir, yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session), score: log.score, companyName: { _ in nil }, indirect: false)
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
            NewsStore(directory: dir, yahoo: y, google: GoogleNewsClient(session: StubProtocol.session), score: log.score, companyName: { _ in "Apple Inc." }, indirect: false)
        }
        let filled = try await makeStore(yahoo()).articles(ticker: "AAPL")
        #expect(filled.count == 3)

        StubProtocol.fail(yahooSearch)
        #expect(try await makeStore(yahoo()).articles(ticker: "AAPL").count == 3) // offline: cache

        // Offline with no cache and no backfill source: error.
        StubProtocol.fail(googleRSS)
        await #expect(throws: APIError.self) {
            try await NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                                score: log.score, companyName: { _ in nil }, indirect: false).articles(ticker: "AAPL")
        }
    }

    @Test func apiClientFiltersDedupsAndAggregates() async throws {
        // Yesterday 12:00 UTC, so a/b/d share a UTC day regardless of when the test runs.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let base = utc.startOfDay(for: now).addingTimeInterval(-12 * 3600)
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
                              score: log.score, companyName: { _ in nil }, indirect: false)
        let api = APIClient(yahoo: yahoo(), store: store, now: { now })

        let week = try await api.articles(ticker: "AAPL", days: 7)
        #expect(week.map(\.headline) == ["AAPL good earnings", "Apple bad news - Reuters"]) // dup + low relevance dropped
        #expect(week[0].relevanceScore == 0.85 && week[1].relevanceScore == 0.85) // 'Apple' is recognised as the company
        #expect(week[1].eventSize == 2 && week[1].eventOutlets == 2)               // Reuters + Bloomberg: one event, two outlets
        #expect(try await api.articles(ticker: "AAPL", days: 30).count == 3)               // adds the 10-day-old one
        #expect(try await api.articles(ticker: "AAPL", days: 7, minRelevance: 0.2).count == 3) // roundup passes at 0.2
        #expect(try await api.articles(ticker: "AAPL", days: 7, limit: 1).count == 1)

        // Two events: 'good earnings' (value 0.8, weight 1) and the Reuters+Bloomberg story (value -0.75, weight
        // B = 1 + 0.5*ln 2 for two outlets). The EWMA is recency-weighted with half-life 7/3 days; the story's first
        // report (Bloomberg) is 2h older than 'good earnings', so its recency weight is r = 0.5^((2/24)/(7/3)) of its
        // weight (independent of `now`).
        let summary = try await api.sentimentSummary(ticker: "AAPL", days: 7)
        #expect(summary.count == 2)
        #expect(summary.labelDistribution == ["POSITIVE": 1, "NEUTRAL": 0, "NEGATIVE": 1])
        let boost = 1 + 0.5 * Foundation.log(2.0)
        #expect(summary.articleCount == 3)
        #expect(abs(summary.meanCompound - (0.8 - 0.75 * boost) / (1 + boost)) < 1e-9)
        let r = pow(0.5, (2.0 / 24.0) / (7.0 / 3.0))
        #expect(abs(summary.ewmaCompound - (0.8 - 0.75 * boost * r) / (1 + boost * r)) < 1e-9)

        let trend = try await api.sentimentTrend(ticker: "AAPL", hours: 24 * 30)
        #expect(trend.points.map(\.articleCount) == [1, 2])   // the old day, then yesterday
        #expect(trend.points.last?.bucket == utc.startOfDay(for: base))
        #expect(abs((trend.points.last?.meanCompound ?? 0) - (0.8 - 0.75 * boost) / (1 + boost)) < 1e-9)
    }

    // MARK: the window and the horizon actually matter

    /// One fresh negative headline (1h old) and three older positives (4 days old).
    private func moodClient(now: Date) -> APIClient {
        StubProtocol.route(yahooSearch, body: searchJSON([
            NewsItem(title: "AAPL bad flash", time: now.addingTimeInterval(-3600)),
            // three different stories (identical headlines would, correctly, be one event)
            NewsItem(title: "AAPL good record iphone sales", time: now.addingTimeInterval(-4 * 86_400)),
            NewsItem(title: "AAPL good services revenue growth", time: now.addingTimeInterval(-4 * 86_400)),
            NewsItem(title: "AAPL good big buyback announced", time: now.addingTimeInterval(-4 * 86_400)),
        ]))
        StubProtocol.fail(googleRSS)
        let closes = (0..<40).map { String(100 + $0) }.joined(separator: ",")
        let stamps = (0..<40).map { String(1_767_225_600 + $0 * 86_400) }.joined(separator: ",")
        StubProtocol.route(yahooChart, body: #"{"chart":{"result":[{"timestamp":[\#(stamps)],"indicators":{"quote":[{"open":[\#(closes)],"high":[\#(closes)],"low":[\#(closes)],"close":[\#(closes)],"volume":[\#((0..<40).map { _ in "1" }.joined(separator: ","))]}]}}]}}"#)
        let store = NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                              score: ScoreLog().score, companyName: { _ in nil }, indirect: false)
        return APIClient(yahoo: yahoo(), store: store, now: { now })
    }

    @Test func horizonsGiveDifferentRecommendations() async throws {
        let api = moodClient(now: Date())
        let d1 = try await api.predictSync(ticker: "AAPL", horizonDays: 1)
        let d5 = try await api.predictSync(ticker: "AAPL", horizonDays: 5)
        let d14 = try await api.predictSync(ticker: "AAPL", horizonDays: 14)
        #expect([d1.recommendation, d5.recommendation, d14.recommendation] == ["FALL", "STABLE", "RISE"])
        #expect(abs(d1.sentimentScore - (-0.6)) < 1e-9)                // only the fresh negative is inside 1 day
        #expect(d1.sentimentScore < d5.sentimentScore && d5.sentimentScore < d14.sentimentScore)
        #expect(abs(d1.confidence - (0.52 + 0.6 * 0.35)) < 1e-9)
        #expect(d14.horizonDays == 14)
    }

    @Test func ewmaChangesWithTheWindow() async throws {
        let api = moodClient(now: Date())
        let seven = try await api.sentimentSummary(ticker: "AAPL", days: 7).ewmaCompound
        let thirty = try await api.sentimentSummary(ticker: "AAPL", days: 30).ewmaCompound
        let five = try await api.sentimentSummary(ticker: "AAPL", days: 5).ewmaCompound
        #expect(thirty - seven > 0.05)   // longer window, slower decay, older positives matter more
        #expect(abs(seven - five) > 0.001)
    }

    // MARK: indirect news: leadership / supply chain / sector found by search

    private func rssItem(_ title: String, _ source: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return "<item><title>\(title) - \(source)</title><link>https://g.test/\(title.replacingOccurrences(of: " ", with: "-"))</link><pubDate>\(f.string(from: date))</pubDate><source url=\"x\">\(source)</source></item>"
    }

    private func indirectClient(now: Date) -> (APIClient, ScoreLog) {
        let log = ScoreLog()
        StubProtocol.route(yahooSearch, body: searchJSON([NewsItem(title: "Nvidia posts record data center revenue", time: now.addingTimeInterval(-3600), tickers: ["NVDA"])]))
        // The same feed answers the first-sight backfill windows and the four indirect searches.
        StubProtocol.route(googleRSS, body: "<rss><channel>" + [
            rssItem("Jensen Huang has been ousted", "WSJ", now.addingTimeInterval(-3600)),
            rssItem("TSMC warns of capacity shortage", "Reuters", now.addingTimeInterval(-7200)),
            rssItem("Chip stocks tumble as rates jump", "CNBC", now.addingTimeInterval(-10_800)),
            rssItem("Local bakery wins award", "Gazette", now.addingTimeInterval(-3600)),
        ].joined() + "</channel></rss>")
        let store = NewsStore(directory: tempDir(), yahoo: yahoo(), google: GoogleNewsClient(session: StubProtocol.session),
                              score: log.score, companyName: { _ in "NVIDIA Corporation" })   // indirect searches on
        return (APIClient(yahoo: yahoo(), store: store, now: { now }), log)
    }

    @Test func indirectNewsIsFoundTaggedAndFilteredByRelevance() async throws {
        let (api, _) = indirectClient(now: Date())
        let at02 = try await api.articles(ticker: "NVDA", days: 30, minRelevance: 0.2)
        let byChannel = Dictionary(uniqueKeysWithValues: at02.map { ($0.channel ?? "", $0.headline) })
        #expect(byChannel["direct"] == "Nvidia posts record data center revenue")
        #expect(byChannel["people"] == "Jensen Huang has been ousted")
        #expect(byChannel["supply"] == "TSMC warns of capacity shortage")
        #expect(byChannel["sector"] == "Chip stocks tumble as rates jump")
        #expect(!at02.contains { $0.headline.contains("bakery") })
        func channels(_ min: Double) async throws -> [String] {
            try await api.articles(ticker: "NVDA", days: 30, minRelevance: min).compactMap(\.channel).sorted()
        }
        #expect(try await channels(0.35) == ["direct", "people", "sector", "supply"])   // default: sector (0.40) still in
        #expect(try await channels(0.5) == ["direct", "people", "supply"])
        #expect(try await channels(0.7) == ["direct", "people"])

        let summary = try await api.sentimentSummary(ticker: "NVDA", days: 30, minRelevance: 0.5)
        #expect(summary.count == 3 && summary.articleCount == 3)                        // direct + leadership + supply chain events
    }

    @Test func indirectSearchesRunOncePerTickerPerSession() async throws {
        let (api, _) = indirectClient(now: Date())
        _ = try await api.articles(ticker: "NVDA", days: 30)
        let first = StubProtocol.hitCount(googleRSS)
        #expect(first == 8)                                                             // 4 backfill windows + 4 indirect searches
        _ = try await api.articles(ticker: "NVDA", days: 30)
        #expect(StubProtocol.hitCount(googleRSS) == first)
    }

    @Test func apiClientRisk() async throws {
        let closes = (0..<40).map { String(100 + $0) }.joined(separator: ",")
        let stamps = (0..<40).map { String(1_767_225_600 + $0 * 86_400) }.joined(separator: ",")
        let json = #"{"chart":{"result":[{"timestamp":[\#(stamps)],"indicators":{"quote":[{"open":[\#(closes)],"high":[\#(closes)],"low":[\#(closes)],"close":[\#(closes)],"volume":[\#((0..<40).map { _ in "1" }.joined(separator: ","))]}]}}]}}"#
        StubProtocol.route(yahooChart, body: json)
        StubProtocol.route("query1.finance.yahoo.com/v8/finance/chart/SPY", body: json)
        let risk = try await APIClient(yahoo: yahoo(), store: NewsStore(directory: tempDir(), yahoo: yahoo(), indirect: false)).riskMetrics(ticker: "AAPL")
        #expect(abs(risk.betaToBenchmark - 1) < 1e-9)   // identical series
        #expect(risk.maxDrawdown == 0 && risk.highWaterMark == 139)
    }

    // MARK: FinBERT model download

    private func sha(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func manifest(corrupt: Bool = false) -> String {
        #"{"version":1,"files":[{"asset":"model.mil","path":"model.mil","size":5,"sha256":"\#(sha("hello"))"},{"asset":"weights__weight.bin","path":"weights/weight.bin","size":5,"sha256":"\#(corrupt ? sha("nope!") : sha("world"))"}]}"#
    }
    private func routeModel(corrupt: Bool = false) {
        StubProtocol.route("models.test/m/manifest.json", body: manifest(corrupt: corrupt))
        StubProtocol.route("models.test/m/model.mil", body: "hello")
        StubProtocol.route("models.test/m/weights__weight.bin", body: "world")
    }
    @MainActor private func modelStore(install: URL, bundled: Bool = false) -> FinBERTModelStore {
        FinBERTModelStore(session: StubProtocol.session, baseURL: URL(string: "https://models.test/m/")!,
                          installURL: install, bundledPresent: bundled)
    }

    @MainActor @Test func modelDownloadInstallsVerifiedFiles() async throws {
        routeModel()
        let install = tempDir().appendingPathComponent("models/FinBERT.mlmodelc")
        let store = modelStore(install: install)
        #expect(store.state == .idle)
        store.startIfNeeded()
        await store.waitUntilFinished()
        #expect(store.state == .ready)
        #expect(try String(contentsOf: install.appendingPathComponent("model.mil"), encoding: .utf8) == "hello")
        #expect(try String(contentsOf: install.appendingPathComponent("weights/weight.bin"), encoding: .utf8) == "world")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: install.deletingLastPathComponent().path)
        #expect(leftovers == ["FinBERT.mlmodelc"])   // no staging dirs left behind
        // A relaunch finds the installed model and does not hit the network.
        StubProtocol.reset()
        #expect(modelStore(install: install).state == .ready)
    }

    @MainActor @Test func modelDownloadRejectsCorruptFile() async throws {
        routeModel(corrupt: true)
        let install = tempDir().appendingPathComponent("models/FinBERT.mlmodelc")
        let store = modelStore(install: install)
        store.startIfNeeded(); await store.waitUntilFinished()
        guard case .failed(let message) = store.state else { Issue.record("expected failure, got \(store.state)"); return }
        #expect(message.contains("verification"))
        #expect(!FileManager.default.fileExists(atPath: install.path))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: install.deletingLastPathComponent().path))?.isEmpty ?? true)
    }

    @MainActor @Test func modelDownloadRetriesAfterFailure() async throws {
        StubProtocol.route("models.test/m/manifest.json", status: 404, body: "")
        let install = tempDir().appendingPathComponent("models/FinBERT.mlmodelc")
        let store = modelStore(install: install)
        store.startIfNeeded(); await store.waitUntilFinished()
        #expect({ if case .failed = store.state { true } else { false } }())
        routeModel()
        store.retry(); await store.waitUntilFinished()
        #expect(store.state == .ready)
    }

    @MainActor @Test func bundledModelSkipsDownload() async throws {
        routeModel()
        let store = modelStore(install: tempDir().appendingPathComponent("m.mlmodelc"), bundled: true)
        store.startIfNeeded(); await store.waitUntilFinished()
        #expect(store.state == .bundled)
        #expect(StubProtocol.hitCount("models.test/m/manifest.json") == 0)
    }
}

extension NewsStore {
    /// Tests reopen a store on the same directory to simulate a relaunch.
    nonisolated var directoryForTests: URL { _directoryForTests }
}
