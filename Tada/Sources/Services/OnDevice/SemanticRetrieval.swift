import Foundation
import NaturalLanguage

/// On-device SEMANTIC retrieval (NLEmbedding sentence embeddings + cosine).
/// Ported verbatim from the FMDiscovery research package (champion exp056); it
/// surfaces the nearest corpus task TYPE regardless of literal word overlap, and
/// supplies the embedding vectors the corpus-coverage selection step compares
/// candidate questions against. Fully on-device.
enum SemanticRetrieval {
    /// Return the k exemplars whose input is semantically nearest to `query`.
    /// Falls back to the caller-supplied Jaccard ordering when sentence
    /// embeddings are unavailable on this device.
    static func nearest(query: String, candidates: [GoldExemplar], k: Int,
                        fallback: (String, Int) -> [GoldExemplar]) -> [GoldExemplar] {
        guard let embedder = NLEmbedding.sentenceEmbedding(for: .english),
              let qVec = embedder.vector(for: query) else {
            return fallback(query, k)
        }
        var scored: [(GoldExemplar, Double)] = []
        for ex in candidates {
            guard let v = embedder.vector(for: ex.input) else {
                // Any missing vector → embeddings unreliable here; bail to Jaccard.
                return fallback(query, k)
            }
            scored.append((ex, cosine(qVec, v)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(k).map { $0.0 }
    }

    /// Embed an arbitrary list of strings on-device. Returns nil if the sentence
    /// embedder is unavailable or any string fails to embed (so callers fall back
    /// safely). Used by the corpus-coverage selection to compare candidate
    /// questions against the corpus axes in embedding space.
    static func vectors(for strings: [String]) -> [[Double]]? {
        guard let embedder = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        var out: [[Double]] = []
        for s in strings {
            guard let v = embedder.vector(for: s) else { return nil }
            out.append(v)
        }
        return out
    }

    /// Public cosine for callers working with raw vectors.
    static func cos(_ a: [Double], _ b: [Double]) -> Double { cosine(a, b) }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }
}
