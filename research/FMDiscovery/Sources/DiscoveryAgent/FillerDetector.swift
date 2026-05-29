import Foundation

/// EXP-017: deterministic detection of WASTED question slots — generic catch-all
/// "filler" phrasings and near-duplicate pairs. The judge's recurring complaint on
/// the best config (exp011) is not only "missed the critical unknown" but that
/// redundant clusters and vague catch-alls "crowd out more valuable questions"
/// (bakery Q1/Q2/Q3/Q7, gp Q3/Q4, guitar Q5/Q7 overlap; "specific features or
/// preferences", "specific requirements" filler). Detection here is purely
/// mechanical (no 3B judgment), so unlike exp009's embedding gap-finder it targets
/// exactly the slots the judge flags, and unlike exp005's FM audit it injects no
/// universal-dimension checklist.
enum FillerDetector {
    /// Lower-cased substrings that signal a generic, non-decision-critical
    /// catch-all question (the judge's recurring "vague filler" pattern).
    static let fillerMarkers: [String] = [
        "any other", "anything else", "any additional", "additional information",
        "additional details", "other details", "specific requirements",
        "specific preferences", "any preferences", "any concerns", "any questions",
        "is there anything", "anything important", "anything we should",
        "any specific features", "any specific requirements", "any specific preferences",
        "anything i should know", "anything else i should", "other factors",
        "specific features or preferences", "specific needs or preferences",
    ]

    static func isFiller(_ q: String) -> Bool {
        let l = q.lowercased()
        return fillerMarkers.contains { l.contains($0) }
    }

    private static let stop: Set<String> = [
        "what", "is", "are", "the", "your", "you", "do", "does", "to", "of", "for",
        "how", "which", "will", "be", "this", "any", "have", "that", "it", "or",
        "and", "in", "on", "would", "like", "with", "want", "specific", "there",
        "already", "their",
    ]

    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) })
    }

    /// Content-word Jaccard between two questions (stop words removed).
    static func jaccard(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        if ta.isEmpty || tb.isEmpty { return 0 }
        let inter = ta.intersection(tb).count
        let uni = ta.union(tb).count
        return Double(inter) / Double(uni)
    }

    /// Indices of WASTED slots: filler questions + the later member of any
    /// near-duplicate pair (content Jaccard ≥ threshold). Capped to leave at
    /// least `keepAtLeast` slots untouched, dropping the lowest-priority weak
    /// slots first (later positions), so a degenerate draft never triggers a
    /// full rewrite.
    static func weakIndices(_ questions: [String], dupThreshold: Double = 0.5, keepAtLeast: Int = 4) -> [Int] {
        var weak = Set<Int>()
        for (i, q) in questions.enumerated() where isFiller(q) { weak.insert(i) }
        for i in 0..<questions.count {
            for j in (i + 1)..<questions.count where jaccard(questions[i], questions[j]) >= dupThreshold {
                weak.insert(j)   // keep the earlier, drop the later duplicate
            }
        }
        let maxWeak = max(0, questions.count - keepAtLeast)
        return Array(weak.sorted().prefix(maxWeak))
    }
}
