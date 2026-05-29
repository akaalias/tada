import Foundation

/// EXP-009: deterministic, task-conditioned coverage-gap detector.
///
/// The recurring judge complaint across exp003-008 is COVERAGE: the strong RAG
/// draft (exp003) is good on every other axis but reliably MISSES the single most
/// decision-critical unknown for the task. Every prior fix let the 3B *judge*
/// which unknown is missing (checklists exp005/006, whole-set adaptation exp008)
/// and the 3B simply lacks that judgment. Here the judgment moves entirely OUT of
/// the model into embedding math: we compare the draft against the concrete gold
/// questions of the nearest exemplars and find the one gold unknown the draft
/// covers LEAST, plus the most-redundant draft slot to sacrifice. The agent then
/// does only a narrow surface rewrite (which the 3B is good at) of that one gold
/// question, leaving the other six draft questions untouched.
enum CoverageRepair {
    /// Returns the concrete gold question whose unknown the draft covers least and
    /// the index of the most-redundant draft slot to replace, or nil when there is
    /// no low-risk repair (embeddings unavailable, draft already covers everything,
    /// or no genuinely redundant slot to spare).
    static func plan(draft: [String], exemplars: [GoldExemplar],
                     coverageThreshold: Double = 0.50,
                     redundancyThreshold: Double = 0.60) -> (missing: String, replaceIndex: Int)? {
        let gold = exemplars.flatMap { $0.questions }
        guard draft.count > 1, !gold.isEmpty,
              let draftVecs = SemanticRetrieval.vectors(for: draft),
              let goldVecs = SemanticRetrieval.vectors(for: gold) else { return nil }

        // Coverage of each gold question = max cosine to ANY draft question.
        // The gold question with the lowest coverage is the most-missing unknown.
        var minCoverage = Double.greatestFiniteMagnitude
        var missingIdx = 0
        for (gi, gv) in goldVecs.enumerated() {
            let cov = draftVecs.map { SemanticRetrieval.cos($0, gv) }.max() ?? 0
            if cov < minCoverage { minCoverage = cov; missingIdx = gi }
        }
        guard minCoverage < coverageThreshold else { return nil }

        // Most-redundant draft slot = the one most similar to another draft question.
        // Sacrificing it loses the least information.
        var maxRedundancy = -Double.greatestFiniteMagnitude
        var replaceIdx = 0
        for i in draftVecs.indices {
            var best = -Double.greatestFiniteMagnitude
            for j in draftVecs.indices where j != i {
                best = max(best, SemanticRetrieval.cos(draftVecs[i], draftVecs[j]))
            }
            if best > maxRedundancy { maxRedundancy = best; replaceIdx = i }
        }
        // Only swap if there is a genuinely redundant slot; otherwise the draft is
        // well-diversified and we leave it intact (no forced, lossy swap).
        guard maxRedundancy >= redundancyThreshold else { return nil }

        return (gold[missingIdx], replaceIdx)
    }
}
