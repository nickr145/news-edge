import Foundation
import Testing
@testable import NewsEdge

struct EmbeddingCodecTests {
    @Test func namesTheCompanyOnlyWhenTheHeadlineOmitsIt() {
        #expect(EmbeddingCodec.text(headline: "Chipmaker's chief executive steps down", company: "NVIDIA Corporation") == "NVIDIA: Chipmaker's chief executive steps down")
        #expect(EmbeddingCodec.text(headline: "Nvidia posts record revenue", company: "NVIDIA Corporation") == "Nvidia posts record revenue")
        #expect(EmbeddingCodec.text(headline: "Anything", company: nil) == "Anything")
    }

    @Test func int8RoundTripKeepsCosineWithinOneHundredth() {
        func unit(_ seed: Double) -> [Float] {
            let v = (0..<384).map { Float(sin(seed * Double($0 + 1))) }
            let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
            return v.map { $0 / n }
        }
        let a = unit(1), b = unit(1.01)
        let q = EmbeddingCodec.cosine(EmbeddingCodec.dequantize(EmbeddingCodec.quantize(a))!, EmbeddingCodec.dequantize(EmbeddingCodec.quantize(b))!)
        #expect(abs(q - EmbeddingCodec.cosine(a, b)) < 0.01)
        #expect(EmbeddingCodec.quantize(a).count == 512) // 384 bytes in base64, same as the web app
    }

    @Test func cosineOfOrthogonalOrZeroVectorsIsZero() {
        #expect(EmbeddingCodec.cosine([1, 0], [0, 1]) == 0)
        #expect(EmbeddingCodec.cosine([0, 0], [1, 0]) == 0)
        #expect(EmbeddingCodec.cosine([1], [1, 0]) == 0)
    }

    @Test func newsConfigLoadsWithTheValuesTheCodeUsedToHardCode() {
        let c = NewsConfig.shared
        #expect(c.events.windowHours == 48 && c.events.lexical.jaccard == 0.5 && c.events.outletWeight.cap == 2.5)
        #expect(c.storylines.windowHours == 72 && c.storylines.dampingFloor == 0.25 && c.storylines.minEvents == 30)
        #expect(c.embedding.dimension == 384 && c.embedding.maxTokens == 64)
    }
}

/// Real Core ML model vs the Python reference cosines in data/embedding_fixtures.json.
/// Skipped (not failed) when MiniLM hasn't been generated or downloaded.
struct SentenceEmbedderTests {
    private struct Fixtures: Decodable {
        struct Pair: Decodable { let label: String; let company: String; let a: String; let b: String; let cosine: Double }
        let pairs: [Pair]
    }

    @Test func coreMLMatchesTheReferenceOnEveryFixturePair() throws {
        guard let embedder = SentenceEmbedder.shared else { return }
        let url = try #require(Bundle.main.url(forResource: "EmbeddingFixtures", withExtension: "json"))
        let pairs = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url)).pairs
        let texts = pairs.flatMap { [EmbeddingCodec.text(headline: $0.a, company: $0.company), EmbeddingCodec.text(headline: $0.b, company: $0.company)] }
        let vecs = try #require(embedder.embed(texts))
        for (i, p) in pairs.enumerated() {
            let got = EmbeddingCodec.cosine(EmbeddingCodec.dequantize(EmbeddingCodec.quantize(vecs[2 * i]))!, EmbeddingCodec.dequantize(EmbeddingCodec.quantize(vecs[2 * i + 1]))!)
            #expect(abs(got - p.cosine) < 0.05, "\(p.a) | \(p.b): \(got) vs \(p.cosine)")
        }
        #expect(vecs.allSatisfy { v in abs(v.reduce(0) { $0 + $1 * $1 } - 1) < 0.01 }) // unit length out of the model
    }
}
