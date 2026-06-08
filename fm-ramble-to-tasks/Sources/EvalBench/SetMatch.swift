import Foundation
import NaturalLanguage

/// Deterministic set-match between a candidate task list and the gold task list.
/// This is the headline ruler: precision / recall / F1 over a one-to-one match by
/// sentence-embedding cosine similarity, plus the zero-task binary case.
public struct SetMatch: Sendable, Codable {
    public let precision: Double
    public let recall: Double
    public let f1: Double
    public let matched: Int
    public let predCount: Int
    public let goldCount: Int
    public let goldEmpty: Bool
    public let zeroTaskCorrect: Bool

    /// Per-case headline quality (0-1). Zero-task is binary; otherwise F1.
    public var quality: Double {
        if goldEmpty { return zeroTaskCorrect ? 1.0 : 0.0 }
        return f1
    }
}

public enum TaskSetMatcher {
    /// Cosine similarity at or above which two task strings count as the same task.
    /// Starting value — calibrate against the seed gold cases.
    public static let defaultThreshold = 0.78

    // Read-only after init; dev-time eval is effectively single-threaded.
    nonisolated(unsafe) private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    public static func match(pred: [String], gold: [String], threshold: Double = defaultThreshold) -> SetMatch {
        let goldEmpty = gold.isEmpty

        // Zero-task and empty-prediction cases are scored directly.
        if goldEmpty || pred.isEmpty {
            let bothEmpty = goldEmpty && pred.isEmpty
            let v = bothEmpty ? 1.0 : 0.0
            return SetMatch(precision: v, recall: v, f1: v, matched: 0,
                            predCount: pred.count, goldCount: gold.count,
                            goldEmpty: goldEmpty, zeroTaskCorrect: bothEmpty)
        }

        // Greedy one-to-one match: each gold task claims its best unused prediction
        // whose similarity clears the threshold.
        var usedPred = Set<Int>()
        var matched = 0
        for g in gold {
            var bestI = -1
            var bestSim = threshold
            for (i, p) in pred.enumerated() where !usedPred.contains(i) {
                let sim = similarity(g, p)
                if sim >= bestSim { bestSim = sim; bestI = i }
            }
            if bestI >= 0 { usedPred.insert(bestI); matched += 1 }
        }

        let precision = Double(matched) / Double(pred.count)
        let recall = Double(matched) / Double(gold.count)
        let f1 = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)
        return SetMatch(precision: precision, recall: recall, f1: f1, matched: matched,
                        predCount: pred.count, goldCount: gold.count,
                        goldEmpty: false, zeroTaskCorrect: false)
    }

    /// Cosine similarity in [-1, 1]; falls back to word-Jaccard if no embedding model.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.compare(b, options: .caseInsensitive) == .orderedSame { return 1.0 }
        if let e = embedding {
            // NLDistanceType.cosine returns cosine DISTANCE (0 = identical).
            let d = e.distance(between: a, and: b, distanceType: .cosine)
            return 1.0 - d
        }
        return jaccard(a, b)
    }

    static func jaccard(_ a: String, _ b: String) -> Double {
        let wa = Set(a.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let wb = Set(b.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !wa.isEmpty || !wb.isEmpty else { return 0 }
        let inter = wa.intersection(wb).count
        let union = wa.union(wb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }
}
