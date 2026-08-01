import Foundation

/// Wraps `GET /ws/news/{ticker}` (app/api/routes_ws.py), which pushes each new
/// `ArticleOut` as its own JSON text frame every ~2s. Reconnect-on-drop is
/// deferred to the handoff brief's "Polish" phase — this just surfaces the
/// raw stream and finishes on error/disconnect.
final class NewsSocket {
    private let session: URLSession
    private let decoder = JSONCoding.makeDecoder()
    private var task: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(ticker: String) -> AsyncThrowingStream<Article, Error> {
        var components = URLComponents(url: APIConfig.webSocketBaseURL, resolvingAgainstBaseURL: false)!
        components.path += "/ws/news/\(ticker)"
        let url = components.url!

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak task] _ in
                task?.cancel(with: .goingAway, reason: nil)
            }
            Task { [decoder] in
                await Self.receiveLoop(task: task, decoder: decoder, continuation: continuation)
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<Article, Error>.Continuation
    ) async {
        while true {
            do {
                let message = try await task.receive()
                let data: Data?
                switch message {
                case .data(let payload):
                    data = payload
                case .string(let text):
                    data = text.data(using: .utf8)
                @unknown default:
                    data = nil
                }
                guard let data else { continue }
                let article = try decoder.decode(Article.self, from: data)
                continuation.yield(article)
            } catch {
                continuation.finish(throwing: error)
                return
            }
        }
    }
}
