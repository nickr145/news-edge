import CryptoKit
import Foundation
import Observation

/// Downloads the compiled FinBERT Core ML model on first launch instead of shipping its 105 MB in the
/// app bundle (see scripts/package_finbert_model.py for the release layout). Until it lands the app
/// scores with NLTagger; when it does, `FinBERTScorer.reload()` switches over and NewsStore re-scores.
@MainActor @Observable
final class FinBERTModelStore {
    static let shared = FinBERTModelStore()

    static let defaultBaseURL = URL(string: "https://github.com/nickr145/news-edge/releases/download/finbert-coreml-v1/")!

    enum State: Equatable {
        case bundled            // model ships inside the app (dev builds); nothing to download
        case ready              // downloaded model installed
        case idle               // not started yet
        case downloading
        case failed(String)
    }

    private(set) var state: State

    private struct Manifest: Decodable {
        struct File: Decodable { let asset: String, path: String, size: Int, sha256: String }
        let version: Int
        let files: [File]
    }

    private let session: URLSession
    private let baseURL: URL
    private let installURL: URL
    private let bundledPresent: Bool
    private var task: Task<Void, Never>?

    init(
        session: URLSession? = nil,
        baseURL: URL = FinBERTModelStore.defaultBaseURL,
        installURL: URL = FinBERTScorer.downloadedModelURL,
        bundledPresent: Bool = Bundle.main.url(forResource: "FinBERT", withExtension: "mlmodelc") != nil
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.allowsExpensiveNetworkAccess = false   // 105 MB: Wi-Fi only
            config.allowsConstrainedNetworkAccess = false // and not in Low Data Mode
            config.timeoutIntervalForResource = 3600
            self.session = URLSession(configuration: config)
        }
        self.baseURL = baseURL
        self.installURL = installURL
        self.bundledPresent = bundledPresent
        self.state = bundledPresent ? .bundled
            : FileManager.default.fileExists(atPath: installURL.path) ? .ready : .idle
    }

    /// Starts the download if there is no model yet. Safe to call repeatedly.
    func startIfNeeded() {
        guard state == .idle || isFailed, task == nil else { return }
        state = .downloading
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    func retry() { startIfNeeded() }

    /// Awaitable for tests.
    func waitUntilFinished() async { await task?.value }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    private func run() async {
        do {
            try await install()
            FinBERTScorer.reload()
            state = .ready
        } catch {
            state = .failed((error as? ModelError)?.message ?? "Couldn't download the sentiment model.")
        }
    }

    private struct ModelError: Error { let message: String }

    private func install() async throws {
        let manifest: Manifest
        do {
            let (data, response) = try await session.data(from: baseURL.appendingPathComponent("manifest.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelError(message: "Model manifest not found.") }
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch let error as ModelError { throw error } catch { throw ModelError(message: "Couldn't reach the model server.") }

        let fm = FileManager.default
        let staging = installURL.deletingLastPathComponent().appendingPathComponent("FinBERT.partial-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for file in manifest.files {
            let (tmp, response) = try await session.download(from: baseURL.appendingPathComponent(file.asset))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelError(message: "Model file \(file.asset) not found.") }
            guard (try fm.attributesOfItem(atPath: tmp.path)[.size] as? Int) == file.size,
                  Self.sha256(of: tmp) == file.sha256 else {
                throw ModelError(message: "Downloaded model failed verification.")
            }
            let dest = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: tmp, to: dest)
        }
        try? fm.removeItem(at: installURL)
        try fm.moveItem(at: staging, to: installURL)   // all-or-nothing: the model dir only appears once complete
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
