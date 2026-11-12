import Foundation

/// Keyless Yahoo Finance client (the same source Apple Stocks leans on).
/// Unofficial endpoints: no SLA, so every call site must tolerate failure.
actor YahooClient {
    static let shared = YahooClient()

    private let session: URLSession
    private var cache: [URL: (at: Date, data: Data)] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 1y of daily bars, oldest first. Cached 5 min (risk + bars + features share it).
    func bars(ticker: String) async throws -> [PriceBar] {
        let url = try makeURL(
            host: "query1.finance.yahoo.com",
            path: "/v8/finance/chart/\(ticker.uppercased())",
            query: ["range": "1y", "interval": "1d"]
        )
        let chart = try decode(ChartResponse.self, from: try await fetch(url, ttl: 300))
        guard let result = chart.chart.result?.first, let q = result.indicators.quote.first else { return [] }
        let stamps = result.timestamp ?? []
        var bars: [PriceBar] = []
        for (i, ts) in stamps.enumerated() {
            guard i < q.close.count, let close = q.close[i], let open = q.open[i],
                  let high = q.high[i], let low = q.low[i] else { continue }
            bars.append(PriceBar(
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                open: open, high: high, low: low, close: close,
                volume: q.volume[i] ?? 0
            ))
        }
        return bars
    }

    /// Latest ~50 news items tagged to the ticker (Yahoo gives days, not months). Cached 60s.
    func news(ticker: String) async throws -> [Article] {
        let url = try makeURL(
            host: "query1.finance.yahoo.com",
            path: "/v1/finance/search",
            query: ["q": ticker.uppercased(), "newsCount": "50", "quotesCount": "0"]
        )
        let search = try decode(SearchResponse.self, from: try await fetch(url, ttl: 60))
        return search.news.compactMap { item in
            guard let link = item.link, let title = item.title, let ts = item.providerPublishTime else { return nil }
            let compound = Analytics.sentiment(title)
            return Article(
                id: Self.stableID(item.uuid ?? link),
                url: link,
                headline: title,
                summary: nil,
                body: nil,
                source: item.publisher,
                publishedAt: Date(timeIntervalSince1970: TimeInterval(ts)),
                sentimentLabel: Analytics.label(compound),
                compound: compound,
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
