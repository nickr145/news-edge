import CoreML
import Foundation

/// Helpers shared by the embedding pipeline. Mirrors frontend/src/lib/local/embeddings.js (text prefixing, int8 storage, cosine).
enum EmbeddingCodec {
    /// Headlines that never name the company ("Chipmaker's chief steps down") embed poorly against ones that do, so name it.
    static func text(headline: String, company: String?) -> String {
        guard NewsConfig.shared.embedding.prefixCompanyWhenMissing, let company else { return headline }
        let name = company.replacingOccurrences(of: "[,.]?\\s+(inc|corp|corporation|co|ltd|plc|holdings|group)\\.?$", with: "",
                                                options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || headline.lowercased().contains(name.lowercased()) { return headline }
        return "\(name): \(headline)"
    }

    /// Direction-only int8 (largest component -> 127, scale not stored because cosine ignores it), base64.
    static func quantize(_ v: [Float]) -> String {
        let peak = v.map { abs($0) }.max() ?? 0
        let k: Float = peak > 0 ? 127 / peak : 0
        return Data(v.map { UInt8(bitPattern: Int8(($0 * k).rounded())) }).base64EncodedString()
    }

    static func dequantize(_ s: String) -> [Float]? {
        Data(base64Encoded: s)?.map { Float(Int8(bitPattern: $0)) / 127 }
    }

    /// Cosine similarity, normalising because dequantized vectors are not unit length.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0 }
        var d: Float = 0, x: Float = 0, y: Float = 0
        for i in a.indices { d += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i] }
        return x > 0 && y > 0 ? Double(d / (x * y).squareRoot()) : 0
    }
}

/// On-device all-MiniLM-L6-v2 via Core ML (see scripts/convert_minilm_coreml.py). `shared` is nil until a model is
/// available (bundled in dev builds, otherwise downloaded by CoreMLModelStore.embedder); callers then stay lexical.
final class SentenceEmbedder: @unchecked Sendable {
    static let releaseURL = URL(string: "https://github.com/nickr145/news-edge/releases/download/minilm-coreml-v1/")!
    static var sequenceLength: Int { NewsConfig.shared.embedding.maxTokens } // must match SEQ_LEN in the conversion script

    static var downloadedModelURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models/MiniLM.mlmodelc", isDirectory: true)
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var instance: SentenceEmbedder?
    nonisolated(unsafe) private static var attempted = false

    static var shared: SentenceEmbedder? {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if !attempted { attempted = true; instance = SentenceEmbedder() }
        return instance
    }

    /// Forget a cached "no model" result so the next `shared` looks again (after a download lands).
    static func reload() { sharedLock.lock(); attempted = false; sharedLock.unlock() }

    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let lock = NSLock()

    private init?() {
        let downloaded = Self.downloadedModelURL
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly // the pooled graph fails to compile for the GPU/ANE on some OS builds, and headlines are tiny
        guard let modelURL = Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc")
                ?? (FileManager.default.fileExists(atPath: downloaded.path) ? downloaded : nil),
              let vocabURL = Bundle.main.url(forResource: "finbert_vocab", withExtension: "txt"), // same uncased BERT vocab
              let tokenizer = WordPieceTokenizer(vocabURL: vocabURL),
              let model = try? MLModel(contentsOf: modelURL, configuration: config)
        else { return nil }
        self.model = model
        self.tokenizer = tokenizer
    }

    /// One unit-length vector per text, or nil if the model fails.
    func embed(_ texts: [String]) -> [[Float]]? {
        lock.lock(); defer { lock.unlock() }
        let n = Self.sequenceLength, dim = NewsConfig.shared.embedding.dimension
        var out: [[Float]] = []
        for text in texts {
            let (ids, mask) = tokenizer.encode(text, length: n)
            guard let inputIDs = try? MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32),
                  let attention = try? MLMultiArray(shape: [1, NSNumber(value: n)], dataType: .int32) else { return nil }
            for i in 0..<n { inputIDs[i] = NSNumber(value: ids[i]); attention[i] = NSNumber(value: mask[i]) }
            guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["input_ids": inputIDs, "attention_mask": attention]),
                  let result = try? model.prediction(from: provider),
                  let vec = result.featureValue(for: "embedding")?.multiArrayValue, vec.count == dim else { return nil }
            out.append((0..<dim).map { vec[$0].floatValue })
        }
        return out
    }
}
