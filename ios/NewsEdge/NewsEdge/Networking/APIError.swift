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
}
