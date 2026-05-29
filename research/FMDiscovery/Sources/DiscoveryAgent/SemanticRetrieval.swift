import Foundation
import NaturalLanguage

/// EXP-007: on-device SEMANTIC retrieval for RAG few-shot. The current best
/// (exp003) selects exemplars by word-overlap Jaccard, which returns near-zero
/// similarity for topically distinct queries (e.g. "Update my resume" vs
/// "Prepare for a job interview" share no literal words, yet are the same task
/// TYPE). NLEmbedding sentence embeddings + cosine surface the nearest task TYPE
/// regardless of vocabulary overlap, so the few-shot demonstrations model the
/// right decision-critical unknowns. Production-safe: fully on-device.
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

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }
}
