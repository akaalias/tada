import Foundation

/// Deterministic, on-device coverage ruler used to rank candidate question sets
/// (EXP-004 best-of-N). The recurring judge complaint is COVERAGE: the 3B drops
/// universal high-value unknowns (budget, timeline, scale/who-for, location,
/// current-state) and clusters redundant questions. Gold sets reliably span these
/// dimensions, so we reward a set for spanning many distinct planning dimensions —
/// weighting the high-value ones — while penalizing redundant clusters and
/// questions that re-ask a fact already stated in the task.
enum CoverageScorer {
    private struct Dim {
        let name: String
        let weight: Double
        let keywords: [String]
    }

    // High-value dimensions (weight 2.0) are the ones the model most often misses
    // and that gold almost always covers. Supporting dimensions weight 1.0.
    private static let dims: [Dim] = [
        Dim(name: "budget", weight: 2.0, keywords: [
            "budget", "cost", "spend", "afford", "price", "money", "financial",
            "income", "expensive", "$", "dollar", "euro", "pay"]),
        Dim(name: "timeline", weight: 2.0, keywords: [
            "when", "deadline", "date", "timeline", "how long", "how soon",
            "by when", "schedule", "urgen", "time frame", "timeframe", "day"]),
        Dim(name: "scale", weight: 2.0, keywords: [
            "how many", "how much", "who is", "who are", "who will", "for whom",
            "people", "guests", "group", "size", "alone", "others", "household",
            "everyone", "attend"]),
        Dim(name: "location", weight: 2.0, keywords: [
            "where", "location", "city", "region", "area", "place", "destination",
            "depart", "from where", "venue", "country", "neighborhood", "local"]),
        Dim(name: "currentState", weight: 2.0, keywords: [
            "already", "before", "currently", "existing", "tried", "experience",
            "so far", "previously", "have you started", "do you have", "current",
            "have you done", "have you ever", "right now"]),
        Dim(name: "goal", weight: 1.0, keywords: [
            "goal", "motivation", "why", "purpose", "hoping", "achieve",
            "objective", "looking to", "want to get", "reason"]),
        Dim(name: "preferences", weight: 1.0, keywords: [
            "prefer", "constraint", "restriction", "avoid", "requirement",
            "limitation", "style", "type of", "kind of", "tone", "theme", "must"]),
        Dim(name: "resources", weight: 1.0, keywords: [
            "hire", "yourself", "diy", "help", "professional", "own", "equipment",
            "tool", "format", "software", "support", "by hand"]),
    ]

    /// Score a set of question titles for a given task input.
    static func score(_ questions: [String], input: String) -> Double {
        let lowered = questions.map { $0.lowercased() }

        // Count how many questions touch each dimension.
        var counts: [String: Int] = [:]
        for q in lowered {
            for dim in dims where dim.keywords.contains(where: { q.contains($0) }) {
                counts[dim.name, default: 0] += 1
            }
        }

        var score = 0.0
        for dim in dims {
            let c = counts[dim.name] ?? 0
            if c > 0 { score += dim.weight }          // reward spanning the dimension
            if c > 2 { score -= Double(c - 2) * 0.75 } // penalize redundant clusters
        }

        // Penalize re-asking a fact already stated in the task: if the input
        // contains a number and a question asks "how many"/"how much", the count
        // is likely already known (e.g. "dinner for 8 friends" → "how many guests?").
        let inputHasNumber = input.rangeOfCharacter(from: .decimalDigits) != nil
            || containsNumberWord(input.lowercased())
        if inputHasNumber {
            for q in lowered where q.contains("how many") || q.contains("how much") {
                score -= 1.0
            }
        }

        return score
    }

    private static func containsNumberWord(_ s: String) -> Bool {
        let words = ["one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve", "dozen",
                     "couple", "few", "several"]
        let tokens = Set(s.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return words.contains(where: tokens.contains)
    }
}
