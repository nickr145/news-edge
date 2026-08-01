import Foundation

/// URLSession-based client for the NewsEdge FastAPI backend.
/// One method per endpoint actually called by `frontend/src/lib/api.js` consumers
/// (TickerPage.jsx, WatchlistPanel.jsx) — see the handoff brief, Task 2.
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONCoding.makeDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - News

    func articles(
        ticker: String,
        days: Int,
        limit: Int = 100,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> [Article] {
        try await get(
            "/api/news/\(ticker)",
            query: [
                "days": "\(days)",
                "limit": "\(limit)",
                "min_relevance": "\(minRelevance)",
                "include_mock": "\(includeMock)",
            ]
        )
    }

    func sentimentSummary(
        ticker: String,
        days: Int,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> SentimentSummary {
        try await get(
            "/api/news/\(ticker)/sentiment",
            query: [
                "days": "\(days)",
                "min_relevance": "\(minRelevance)",
                "include_mock": "\(includeMock)",
            ]
        )
    }

    func sentimentTrend(
        ticker: String,
        hours: Int,
        minRelevance: Double = 0.35,
        includeMock: Bool = false
    ) async throws -> SentimentTrend {
        try await get(
            "/api/news/\(ticker)/trend",
            query: [
                "hours": "\(hours)",
                "min_relevance": "\(minRelevance)",
                "include_mock": "\(includeMock)",
            ]
        )
    }

    @discardableResult
    func subscribe(
        ticker: String,
        backfillDays: Int = 30,
        webBackfill: Bool = true
    ) async throws -> SubscribeResponse {
        try await postEmpty(
            "/api/news/subscribe/\(ticker)",
            query: [
                "backfill_days": "\(backfillDays)",
                "web_backfill": "\(webBackfill)",
            ]
        )
    }

    // MARK: - Price

    func priceBars(ticker: String, limit: Int) async throws -> [PriceBar] {
        try await get("/api/price/\(ticker)/bars", query: ["limit": "\(limit)"])
    }

    func riskMetrics(ticker: String, benchmark: String = "SPY", days: Int = 365) async throws -> RiskMetrics {
        try await get(
            "/api/price/\(ticker)/risk",
            query: ["benchmark": benchmark, "days": "\(days)"]
        )
    }

    // MARK: - Prediction

    func predictSync(ticker: String, horizonDays: Int) async throws -> Prediction {
        try await post("/api/predict/\(ticker)/sync", body: PredictionRequest(horizonDays: horizonDays))
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(method: "GET", path: path, query: query)
        return try await send(request)
    }

    private func postEmpty<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(method: "POST", path: path, query: query)
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String] = [:]
    ) async throws -> T {
        var request = try buildRequest(method: "POST", path: path, query: query)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func buildRequest(method: String, path: String, query: [String: String]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path += path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
