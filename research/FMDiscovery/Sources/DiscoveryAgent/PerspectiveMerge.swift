import Foundation
import Contract

/// EXP-021: deterministic merge for the prompt-diverse perspective ensemble.
/// Every prior multi-sample config (best-of-N exp004, self-consistency exp010,
/// tournament exp012, corpus-select exp020) drew its samples from ONE prompt at
/// different TEMPERATURES — and exp010's datum is that those samples all collapse
/// onto the SAME generic modal cluster, so no aggregation/selection over them
/// recovers coverage. This merge instead operates over sets generated from
/// systematically DIFFERENT generation FRAMES (execution / scope / domain-expert),
/// each of which steers the model into a different region of decision-space, so
/// their UNION spans dimensions no single modal draw produces. Crucially the merge
/// is DETERMINISTIC (no 3B selection/ranking/critique pass to compound weak
/// judgment): take each frame's questions in its OWN emission order (the model's
/// own priority) round-robin across frames, skipping filler and near-duplicates.
enum PerspectiveMerge {
    static func merge(_ sets: [[DiscoveryQuestion]], count: Int) -> [DiscoveryQuestion] {
        // Interleave by emission position so each frame's top-priority questions
        // are considered first: frame0[0], frame1[0], frame2[0], frame0[1], ...
        let maxLen = sets.map { $0.count }.max() ?? 0
        var ordered: [DiscoveryQuestion] = []
        for pos in 0..<maxLen {
            for set in sets where pos < set.count { ordered.append(set[pos]) }
        }
        guard !ordered.isEmpty else { return [] }

        // Optional embedding vectors for paraphrase-level dedup (Jaccard catches
        // lexical overlap; cosine catches reworded duplicates when available).
        let vecs = SemanticRetrieval.vectors(for: ordered.map { $0.title })

        func tooClose(_ i: Int, _ chosen: [Int]) -> Bool {
            for c in chosen {
                if FillerDetector.jaccard(ordered[i].title, ordered[c].title) >= 0.5 { return true }
                if let v = vecs, SemanticRetrieval.cos(v[i], v[c]) >= 0.80 { return true }
            }
            return false
        }

        var chosen: [Int] = []
        for i in ordered.indices {
            if chosen.count == count { break }
            if FillerDetector.isFiller(ordered[i].title) { continue }
            if tooClose(i, chosen) { continue }
            chosen.append(i)
        }
        // Pad (relaxing the filters) if dedup left us short of count.
        if chosen.count < count {
            for i in ordered.indices where !chosen.contains(i) {
                if chosen.count == count { break }
                chosen.append(i)
            }
        }
        return chosen.map { ordered[$0] }
    }
}
