import Foundation

/// Set-match between a candidate task list and the gold task list. The headline
/// ruler: precision / recall / F1 over a one-to-one match, plus the zero-task
/// binary case. The match count is supplied by the (paraphrase-aware) Sonnet judge
/// via `fromMatched`; `match` is a deterministic lexical fallback for offline runs.
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
    /// Build a SetMatch from a known matched count (e.g. the judge's count).
    public static func fromMatched(_ matched: Int, predCount: Int, goldCount: Int) -> SetMatch {
        let goldEmpty = goldCount == 0
        if goldEmpty || predCount == 0 {
            let bothEmpty = goldEmpty && predCount == 0
            let v = bothEmpty ? 1.0 : 0.0
            return SetMatch(precision: v, recall: v, f1: v, matched: 0,
                            predCount: predCount, goldCount: goldCount,
                            goldEmpty: goldEmpty, zeroTaskCorrect: bothEmpty)
        }
        let m = max(0, min(matched, min(predCount, goldCount)))
        let precision = Double(m) / Double(predCount)
        let recall = Double(m) / Double(goldCount)
        let f1 = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)
        return SetMatch(precision: precision, recall: recall, f1: f1, matched: m,
                        predCount: predCount, goldCount: goldCount,
                        goldEmpty: false, zeroTaskCorrect: false)
    }

    /// Deterministic fallback (offline / no API key): greedy one-to-one match on
    /// content-word overlap. Approximate — the real matcher is the Sonnet judge,
    /// which is paraphrase-aware. Used only when the judge is unavailable.
    public static let lexicalThreshold = 0.6

    public static func match(pred: [String], gold: [String]) -> SetMatch {
        fromMatched(lexicalMatched(pred: pred, gold: gold), predCount: pred.count, goldCount: gold.count)
    }

    public static func lexicalMatched(pred: [String], gold: [String], threshold: Double = lexicalThreshold) -> Int {
        if gold.isEmpty || pred.isEmpty { return 0 }
        var used = Set<Int>()
        var matched = 0
        for g in gold {
            var bestI = -1
            var best = threshold
            for (i, p) in pred.enumerated() where !used.contains(i) {
                let s = similarity(g, p)
                if s >= best { best = s; bestI = i }
            }
            if bestI >= 0 { used.insert(bestI); matched += 1 }
        }
        return matched
    }

    private static let stop: Set<String> = [
        "the", "a", "an", "to", "of", "for", "and", "or", "my", "your", "i", "is",
        "it", "that", "this", "with", "on", "in", "at", "be", "do", "get", "got",
        "some", "please", "need", "should", "up", "out", "about", "so", "just",
    ]
    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !stop.contains($0) })
    }
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a.compare(b, options: .caseInsensitive) == .orderedSame { return 1.0 }
        let ta = tokens(a), tb = tokens(b)
        if ta.isEmpty || tb.isEmpty { return 0 }
        // Overlap coefficient: lenient to length/detail differences.
        return Double(ta.intersection(tb).count) / Double(min(ta.count, tb.count))
    }
}
