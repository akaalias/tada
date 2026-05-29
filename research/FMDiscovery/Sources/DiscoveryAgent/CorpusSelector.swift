import Foundation
import Contract

/// EXP-020: corpus-grounded selection over an over-generated candidate pool.
/// The persistent wall is that the 3B cannot decide WHICH unknown is decision-
/// critical, so it spends slots on generic catch-alls and drops the slot that
/// matters. Every prior SELECTION over the 3B's own multi-samples failed because
/// the selection SIGNAL was itself weak 3B judgment (self-rated importance exp002,
/// pairwise tournament exp012, cross-sample frequency exp010) or a blunt heuristic
/// (keyword coverage exp004, embedding gap to a SINGLE gold exp009). This selector
/// is different: it ranks each candidate by how much it RESEMBLES the questions
/// Sonnet ACTUALLY asks for the nearest task types (the `corpus/` reference set),
/// in on-device embedding space. A 3B generic catch-all ("any other preferences?")
/// has LOW max-similarity to Sonnet's sharp task-specific questions, so it is
/// demoted; a tail question that matches a real Sonnet unknown ("which city will
/// you depart from?") scores high and is surfaced. The OUTPUT questions are all
/// 3B-generated fresh — the corpus questions are used only as a similarity prior
/// for RANKING, never copied or templated into the output.
enum CorpusSelector {
    /// Pick `count` candidates that best resemble the Sonnet reference questions,
    /// with greedy redundancy suppression in embedding space. Falls back to the
    /// first `count` candidates if embeddings or references are unavailable.
    static func select(candidates: [DiscoveryQuestion], references: [String], count: Int) -> [DiscoveryQuestion] {
        guard candidates.count > count, !references.isEmpty,
              let candVecs = SemanticRetrieval.vectors(for: candidates.map { $0.title }),
              let refVecs = SemanticRetrieval.vectors(for: references) else {
            return Array(candidates.prefix(count))
        }

        // Score each candidate = max cosine similarity to any Sonnet reference question.
        var scored: [(idx: Int, score: Double)] = []
        for (i, cv) in candVecs.enumerated() {
            var best = 0.0
            for rv in refVecs { best = max(best, SemanticRetrieval.cos(cv, rv)) }
            scored.append((idx: i, score: best))
        }
        scored.sort { $0.score > $1.score }

        // Greedy select highest-resemblance candidates, skipping near-duplicates of
        // anything already chosen (embedding cosine >= threshold) to keep the set diverse.
        let redundancyThreshold = 0.80
        var chosen: [Int] = []
        for s in scored {
            if chosen.count == count { break }
            let cv = candVecs[s.idx]
            let tooClose = chosen.contains { SemanticRetrieval.cos(cv, candVecs[$0]) >= redundancyThreshold }
            if !tooClose { chosen.append(s.idx) }
        }
        // Pad (relaxing the redundancy filter) if dedup left us short of count.
        if chosen.count < count {
            for s in scored where !chosen.contains(s.idx) {
                if chosen.count == count { break }
                chosen.append(s.idx)
            }
        }
        return chosen.map { candidates[$0] }
    }
}
