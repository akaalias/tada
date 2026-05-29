import Foundation

/// EXP-010: self-consistency consensus selection.
///
/// The judge dings the best config (exp003) in nearly every case for the SAME
/// two mechanical faults that a single sample produces: (a) REDUNDANCY — two
/// near-duplicate questions (gp date/time x2, tax Q1/Q4 overlap), and (b) wasted
/// slots on ONE-OFF NICHE questions (weekly maintenance time, areas to avoid
/// driving, 5-10yr career goals) that crowd out a decision-critical unknown.
///
/// Hypothesis: the decision-critical planning unknowns are HIGH-PROBABILITY for a
/// task type, so they recur across independent samples, while idiosyncratic noise
/// does not. Drawing N independent RAG sets and keeping the questions with the
/// broadest CROSS-SAMPLE agreement should (1) collapse redundancy — each retained
/// cluster is one distinct unknown — and (2) drop the one-off niche slots, freeing
/// room for the recurring critical unknowns. Selection is deterministic Swift over
/// embeddings: a NEW criticality signal (cross-sample frequency), distinct from
/// exp002 (model self-rated importance) and exp004 (whole-set keyword scoring).
enum SelfConsistency {
    struct Item: Sendable {
        let text: String
        let requiresExternalAction: Bool
        let sample: Int      // which independent sample it came from
        let position: Int    // 0-based position within its sample
    }

    struct Selection: Sendable {
        let text: String
        let requiresExternalAction: Bool
    }

    /// Cluster all sampled questions by embedding similarity, score each cluster by
    /// how many DISTINCT samples it appears in (consensus), and return the 7 highest
    /// as natural, deduped questions. Returns nil if embeddings are unavailable so
    /// the caller can fall back to a single sample.
    static func select(_ items: [Item], count: Int = 7,
                       mergeThreshold: Double = 0.62) -> [Selection]? {
        guard !items.isEmpty,
              let vecs = SemanticRetrieval.vectors(for: items.map { $0.text }) else { return nil }

        // Greedy clustering: assign each item to the first cluster whose centroid it
        // is close enough to, else start a new cluster. Stable input order keeps it
        // deterministic.
        var clusters: [[Int]] = []          // indices into items
        var centroids: [[Double]] = []
        for i in items.indices {
            var bestC = -1
            var bestSim = mergeThreshold
            for (c, cen) in centroids.enumerated() {
                let s = SemanticRetrieval.cos(vecs[i], cen)
                if s >= bestSim { bestSim = s; bestC = c }
            }
            if bestC >= 0 {
                clusters[bestC].append(i)
                centroids[bestC] = mean(clusters[bestC].map { vecs[$0] })
            } else {
                clusters.append([i]); centroids.append(vecs[i])
            }
        }

        // Score: primary = number of distinct samples (consensus breadth); tiebreak =
        // earlier average position (the model puts salient unknowns first); then size.
        func distinctSamples(_ c: [Int]) -> Int { Set(c.map { items[$0].sample }).count }
        func avgPosition(_ c: [Int]) -> Double {
            Double(c.reduce(0) { $0 + items[$1].position }) / Double(c.count)
        }
        let ranked = clusters.enumerated().sorted { a, b in
            let da = distinctSamples(a.element), db = distinctSamples(b.element)
            if da != db { return da > db }
            let pa = avgPosition(a.element), pb = avgPosition(b.element)
            if pa != pb { return pa < pb }
            return a.element.count > b.element.count
        }.map { $0.element }

        let chosen = Array(ranked.prefix(count))

        // Represent each chosen cluster by its most-central member (closest to the
        // cluster centroid) for the most canonical phrasing; majority vote the
        // external-action flag. Order final questions by average original position.
        var selections: [(sel: Selection, order: Double)] = []
        for c in chosen {
            let cen = mean(c.map { vecs[$0] })
            let rep = c.max { SemanticRetrieval.cos(vecs[$0], cen) < SemanticRetrieval.cos(vecs[$1], cen) }!
            let extTrue = c.filter { items[$0].requiresExternalAction }.count
            let ext = extTrue * 2 > c.count
            selections.append((Selection(text: items[rep].text, requiresExternalAction: ext),
                               avgPosition(c)))
        }
        selections.sort { $0.order < $1.order }
        return selections.map { $0.sel }
    }

    private static func mean(_ vs: [[Double]]) -> [Double] {
        guard let first = vs.first else { return [] }
        var acc = [Double](repeating: 0, count: first.count)
        for v in vs { for i in v.indices { acc[i] += v[i] } }
        for i in acc.indices { acc[i] /= Double(vs.count) }
        return acc
    }
}
