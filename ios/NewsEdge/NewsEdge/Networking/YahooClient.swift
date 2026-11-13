import Foundation

/// Keyless market-data client. Primary source is Yahoo Finance (the feed Apple Stocks leans on);
/// daily bars fall back to Nasdaq's historical-quotes API, and the last good bars are kept on disk so a flaky or offline
/// network still shows a chart. Yahoo's endpoints are unofficial (no SLA), so every call site
/// must tolerate failure.
actor YahooClient {
    static let shared = YahooClient()

    private let session: URLSession
    private let barsDirectory: URL
    private var cache: [URL: (at: Date, data: Data)] = [:]

    init(session: URLSession = .shared, barsDirectory: URL? = nil) {
        self.session = session
        self.barsDirectory = barsDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("bars", isDirectory: true)
    }

    /// ~1y of daily bars, oldest first. Yahoo, then Nasdaq, then the last bars saved on disk.
    /// Returns `[]` for a symbol nobody knows; throws only if every source failed and nothing is cached.
    func bars(ticker: String) async throws -> [PriceBar] {
        let symbol = Analytics.yahooSymbol(ticker)
        var failure: Error?
        do {
            let bars = try await yahooBars(symbol)
            if !bars.isEmpty { saveBars(bars, symbol: symbol); return bars }
        } catch { failure = error }
        if let bars = try? await nasdaqBars(symbol), !bars.isEmpty {
            saveBars(bars, symbol: symbol)
            return bars
        }
        if let cached = loadBars(symbol), !cached.isEmpty { return cached }
        if let failure { throw failure }
        return []
    }

    /// Latest ~50 news items tagged to the ticker (Yahoo gives days, not months), unscored. Cached 60s.
    func news(ticker: String) async throws -> [Article] {
        let url = try makeURL(
            host: "query1.finance.yahoo.com",
            path: "/v1/finance/search",
            query: ["q": Analytics.yahooSymbol(ticker), "newsCount": "50", "quotesCount": "0"]
        )
        let search = try decode(SearchResponse.self, from: try await fetch(url, ttl: 60))
        return search.news.compactMap { item in
            guard let link = item.link, let title = item.title, let ts = item.providerPublishTime else { return nil }
            return Article(
                id: Self.stableID(item.uuid ?? link),
                url: link,
                headline: title,
                summary: nil,
                body: nil,
                source: item.publisher,
                publishedAt: Date(timeIntervalSince1970: TimeInterval(ts)),
                sentimentLabel: nil,   // scored by NewsStore, only for articles it hasn't seen
                compound: nil,
                relevanceScore: nil,
                sourceWeight: Analytics.sourceWeight(item.publisher),
                nearEarnings: nil,
                isSecFiling: nil,
                symbols: item.relatedTickers ?? []
            )
        }
    }

    /// Deterministic positive Int (FNV-1a, 53 bits) so cached articles keep a stable identity.
    nonisolated static func stableID(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(h & ((1 << 53) - 1))
    }

    // MARK: - Sources

    private func yahooBars(_ symbol: String) async throws -> [PriceBar] {
        let url = try makeURL(
            host: "query1.finance.yahoo.com",
            path: "/v8/finance/chart/\(symbol)",
            query: ["range": "1y", "interval": "1d"]
        )
        let data: Data
        do { data = try await fetch(url, ttl: 300) } catch APIError.http(status: 404, _) { return [] } // unknown symbol
        let chart = try decode(ChartResponse.self, from: data)
        guard let result = chart.chart.result?.first, let q = result.indicators.quote.first else { return [] }
        var bars: [PriceBar] = []
        for (i, ts) in (result.timestamp ?? []).enumerated() {
            // Arrays should all be as long as `timestamp`; a short one (malformed response) skips the candle.
            guard i < q.close.count, i < q.open.count, i < q.high.count, i < q.low.count,
                  let close = q.close[i], let open = q.open[i], let high = q.high[i], let low = q.low[i] else { continue }
            bars.append(PriceBar(
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                open: open, high: high, low: low, close: close,
                volume: (i < q.volume.count ? q.volume[i] : nil) ?? 0
            ))
        }
        return bars
    }

    /// Nasdaq historical quotes (US symbols; stocks, then ETFs such as the SPY benchmark).
    private func nasdaqBars(_ symbol: String) async throws -> [PriceBar] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(identifier: "UTC"); day.dateFormat = "yyyy-MM-dd"
        for assetClass in ["stocks", "etf"] {
            let url = try makeURL(host: "api.nasdaq.com", path: "/api/quote/\(symbol.replacingOccurrences(of: "-", with: "."))/historical", query: [
                "assetclass": assetClass, "limit": "400",
                "fromdate": day.string(from: Date().addingTimeInterval(-370 * 86_400)), "todate": day.string(from: Date()),
            ])
            let bars = Self.parseNasdaq(try await fetch(url, ttl: 300))
            if !bars.isEmpty { return bars }
        }
        return []
    }

    /// `{"data":{"tradesTable":{"rows":[{"date":"11/10/2026","close":"$348.51","volume":"29,756,060",...}]}}}`, newest first.
    nonisolated static func parseNasdaq(_ data: Data) -> [PriceBar] {
        struct Payload: Decodable {
            struct Row: Decodable { let date, close, volume, open, high, low: String }
            struct Table: Decodable { let rows: [Row]? }
            struct Inner: Decodable { let tradesTable: Table? }
            let data: Inner?
        }
        guard let rows = (try? JSONDecoder().decode(Payload.self, from: data))?.data?.tradesTable?.rows else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC"); formatter.dateFormat = "MM/dd/yyyy"
        func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) }
        return rows.compactMap { r in
            guard let date = formatter.date(from: r.date), let o = number(r.open), let h = number(r.high),
                  let l = number(r.low), let c = number(r.close) else { return nil }
            return PriceBar(timestamp: date, open: o, high: h, low: l, close: c, volume: number(r.volume) ?? 0)
        }.reversed()
    }

    // MARK: - Disk cache of last good bars

    private func barsFile(_ symbol: String) -> URL { barsDirectory.appendingPathComponent("\(symbol).json") }

    private func saveBars(_ bars: [PriceBar], symbol: String) {
        try? FileManager.default.createDirectory(at: barsDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(bars).write(to: barsFile(symbol), options: .atomic)
    }

    private func loadBars(_ symbol: String) -> [PriceBar]? {
        (try? Data(contentsOf: barsFile(symbol))).flatMap { try? JSONDecoder().decode([PriceBar].self, from: $0) }
    }

    // MARK: - Plumbing

    private func makeURL(host: String, path: String, query: [String: String]) throws -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = path
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { throw APIError.invalidURL }
        return url
    }

    private func fetch(_ url: URL, ttl: TimeInterval) async throws -> Data {
        if let hit = cache[url], Date().timeIntervalSince(hit.at) < ttl { return hit.data }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent") // Yahoo rejects the default CFNetwork UA
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: nil)
        }
        cache[url] = (Date(), data)
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.decoding(error) }
    }
}

// MARK: - Wire types

private nonisolated struct ChartResponse: Decodable {
    struct Chart: Decodable { let result: [Result]? }
    struct Result: Decodable {
        let timestamp: [Int]?
        let indicators: Indicators
    }
    struct Indicators: Decodable { let quote: [Quote] }
    struct Quote: Decodable {
        let open: [Double?]
        let high: [Double?]
        let low: [Double?]
        let close: [Double?]
        let volume: [Double?]
    }
    let chart: Chart
}

private nonisolated struct SearchResponse: Decodable {
    struct Item: Decodable {
        let uuid: String?
        let title: String?
        let publisher: String?
        let link: String?
        let providerPublishTime: Int?
        let relatedTickers: [String]?
    }
    let news: [Item]
}
