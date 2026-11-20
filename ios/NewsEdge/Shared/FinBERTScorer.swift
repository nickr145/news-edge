import CoreML
import Foundation

/// BERT uncased tokenizer (ProsusAI/finbert vocab): BasicTokenizer + WordPiece.
struct WordPieceTokenizer {
    let vocab: [String: Int]
    private let cls = 101, sep = 102, pad = 0, unk = 100

    init?(vocabURL: URL) {
        guard let text = try? String(contentsOf: vocabURL, encoding: .utf8) else { return nil }
        var vocab: [String: Int] = [:]
        for (i, token) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where !token.isEmpty {
            vocab[String(token)] = i
        }
        self.vocab = vocab
    }

    /// `[CLS] ... [SEP]` padded/truncated to `length`, plus the attention mask.
    func encode(_ text: String, length: Int) -> (ids: [Int32], mask: [Int32]) {
        var ids = [cls]
        for word in basicTokens(text) { ids += wordPieces(word) }
        ids = Array(ids.prefix(length - 1)) + [sep]
        let mask = [Int32](repeating: 1, count: ids.count) + [Int32](repeating: 0, count: length - ids.count)
        return ((ids + [Int](repeating: pad, count: length - ids.count)).map(Int32.init), mask)
    }

    /// Lowercase, strip accents, split on whitespace and punctuation (BERT BasicTokenizer).
    private func basicTokens(_ text: String) -> [String] {
        let folded = text.lowercased().decomposedStringWithCanonicalMapping
        var tokens: [String] = [], current = ""
        func flush() { if !current.isEmpty { tokens.append(current); current = "" } }
        for scalar in folded.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark || scalar.value == 0 || scalar.value == 0xFFFD { continue }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.properties.generalCategory == .control {
                flush()
            } else if isPunctuation(scalar) {
                flush()
                tokens.append(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        return tokens
    }

    private func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if (33...47).contains(v) || (58...64).contains(v) || (91...96).contains(v) || (123...126).contains(v) { return true }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    private func wordPieces(_ word: String) -> [Int] {
        let chars = Array(word)
        guard chars.count <= 100 else { return [unk] }
        var pieces: [Int] = [], start = 0
        while start < chars.count {
            var end = chars.count, found: Int?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(chars[start..<end])
                if let id = vocab[piece] { found = id; break }
                end -= 1
            }
            guard let id = found else { return [unk] }
            pieces.append(id)
            start = end
        }
        return pieces
    }
}

/// On-device FinBERT via Core ML (see scripts/convert_finbert_coreml.py).
/// `shared` is nil when no model is available (neither bundled nor downloaded by
/// CoreMLModelStore); callers fall back to NLTagger. Call `reload()` once a download lands.
final class FinBERTScorer: @unchecked Sendable {
    static let sequenceLength = 64 // must match SEQ_LEN in the conversion script

    /// Where CoreMLModelStore installs the downloaded, compiled model.
    static var downloadedModelURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models/FinBERT.mlmodelc", isDirectory: true)
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var instance: FinBERTScorer?
    nonisolated(unsafe) private static var attempted = false

    static var shared: FinBERTScorer? {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if !attempted { attempted = true; instance = FinBERTScorer() }
        return instance
    }

    /// Forget a cached "no model" result (or a stale instance) so the next `shared` looks again.
    static func reload() {
        sharedLock.lock(); attempted = false; sharedLock.unlock()
    }

    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let lock = NSLock()
    private var memo: [String: Double] = [:]

    private init?() {
        let downloaded = Self.downloadedModelURL
        guard let modelURL = Bundle.main.url(forResource: "FinBERT", withExtension: "mlmodelc")
                ?? (FileManager.default.fileExists(atPath: downloaded.path) ? downloaded : nil),
              let vocabURL = Bundle.main.url(forResource: "finbert_vocab", withExtension: "txt"),
              let tokenizer = WordPieceTokenizer(vocabURL: vocabURL),
              let model = try? MLModel(contentsOf: modelURL)
        else { return nil }
        self.model = model
        self.tokenizer = tokenizer
    }

    /// P(positive) − P(negative), -1...1 (same convention as the backend's FinBERT path).
    func score(_ text: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        if let hit = memo[text] { return hit }
        let (ids, mask) = tokenizer.encode(text, length: Self.sequenceLength)
        guard let inputIDs = try? MLMultiArray(shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32),
              let attention = try? MLMultiArray(shape: [1, NSNumber(value: Self.sequenceLength)], dataType: .int32)
        else { return nil }
        for i in 0..<Self.sequenceLength {
            inputIDs[i] = NSNumber(value: ids[i])
            attention[i] = NSNumber(value: mask[i])
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["input_ids": inputIDs, "attention_mask": attention]),
              let out = try? model.prediction(from: provider),
              let probs = out.featureValue(for: "probs")?.multiArrayValue, probs.count >= 2
        else { return nil }
        let value = probs[0].doubleValue - probs[1].doubleValue // order: positive, negative, neutral
        memo[text] = value
        return value
    }
}
