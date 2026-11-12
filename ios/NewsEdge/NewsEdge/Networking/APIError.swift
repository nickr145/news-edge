import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case http(status: Int, body: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build a valid request URL."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .http(let status, let body):
            return "Request failed with status \(status)\(body.map { ": \($0)" } ?? "")."
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// Short, user-facing text for the ticker screen's error banner.
    var userMessage: String {
        switch self {
        case .transport(let error):
            return (error as? URLError)?.code == .notConnectedToInternet
                ? "You're offline. Retrying…" : "Network problem. Retrying…"
        case .http(let status, _):
            return status == 429 ? "The data source is rate-limiting requests. Retrying…"
                                 : "Data source error (\(status)). Retrying…"
        default:
            return "Failed to load data. Retrying…"
        }
    }
}
