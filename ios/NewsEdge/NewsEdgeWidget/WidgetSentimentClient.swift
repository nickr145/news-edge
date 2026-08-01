import Foundation

/// Deliberately self-contained rather than sharing the app target's
/// Models/Networking code: widget extensions have a tight memory budget and
/// keeping this target's file membership independent avoids fragile
/// multi-target file-sharing setup in the Xcode project. The sentiment
/// summary payload has no datetime fields, so a plain JSONDecoder is enough
/// (no need for the app target's custom ISO8601 handling).
struct WidgetTickerSentiment: Identifiable {
    var id: String { ticker }
    let ticker: String
    let ewmaCompound: Double?
    let count: Int
}

private struct SentimentSummaryPayload: Decodable {
    let count: Int
    let ewmaCompound: Double

    enum CodingKeys: String, CodingKey {
        case count
        case ewmaCompound = "ewma_compound"
    }
}

enum WidgetAPI {
    static var baseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8000")!
        #else
        return URL(string: "https://news-edge-production.up.railway.app")!
        #endif
    }

    static func fetchSentiment(ticker: String, days: Int = 7) async -> WidgetTickerSentiment {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path += "/api/news/\(ticker)/sentiment"
        components.queryItems = [URLQueryItem(name: "days", value: "\(days)")]

        guard let url = components.url else {
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: nil, count: 0)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let payload = try JSONDecoder().decode(SentimentSummaryPayload.self, from: data)
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: payload.ewmaCompound, count: payload.count)
        } catch {
            return WidgetTickerSentiment(ticker: ticker, ewmaCompound: nil, count: 0)
        }
    }
}
