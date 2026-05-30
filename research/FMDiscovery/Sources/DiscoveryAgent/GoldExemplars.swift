import Foundation

/// Hard-coded non-dev gold examples used for retrieval-augmented few-shot (EXP-003).
/// These are all from the full-30 set but NOT in the dev-10 subset, so they
/// cannot leak test answers into the evaluation.
struct GoldExemplar: Sendable {
    let input: String
    let title: String
    let questions: [String]
    /// Short decision-critical dimension labels, one per gold question. Used by
    /// EXP-006 to build a TASK-CONDITIONED coverage checklist (aggregated across
    /// the nearest exemplars) — the dimensions that strong sets probe for this
    /// task TYPE, not a universal hard-coded list.
    let dimensions: [String]
}

enum GoldExemplars {
    static let all: [GoldExemplar] = [
        GoldExemplar(
            input: "Renovate my kitchen",
            title: "Renovate My Kitchen",
            questions: [
                "What is your total budget for the renovation?",
                "What is your target completion date?",
                "Which parts of the kitchen are you renovating?",
                "Are you hiring contractors or doing it yourself?",
                "Do you already have a design style in mind?",
                "Have you already purchased any materials or appliances?",
                "Do you need to obtain permits for this renovation?"
            ],
            dimensions: ["budget", "timeline / deadline", "scope (what parts)", "DIY vs hiring help", "style / preferences", "current progress / what's done", "permits / external requirements"]
        ),
        GoldExemplar(
            input: "Prepare for a software engineering job interview",
            title: "Prepare for a Software Engineering Job Interview",
            questions: [
                "What company are you interviewing with?",
                "What is the seniority level of the role?",
                "When is your interview scheduled?",
                "What stage of the interview process are you in?",
                "Which technical areas do you feel least confident in?",
                "What is your primary programming language for this interview?",
                "Have you done any preparation so far?"
            ],
            dimensions: ["target / who (company)", "scale / level (seniority)", "timeline / deadline", "process stage / current state", "weak areas / focus", "primary tools / skills", "preparation already done"]
        ),
        GoldExemplar(
            input: "Move to a new apartment across the city",
            title: "Move to a New Apartment Across the City",
            questions: [
                "When is your target move-out date?",
                "Have you already found the new apartment?",
                "How much stuff do you have to move?",
                "Are you planning to hire professional movers?",
                "What is your budget for the move?",
                "Do you have any fragile or special items that need extra care?",
                "Are there any services you need to transfer or set up at the new place?"
            ],
            dimensions: ["timeline / deadline", "current state (place secured?)", "scale / volume", "DIY vs hiring help", "budget", "special items / constraints", "dependencies to set up"]
        ),
        GoldExemplar(
            input: "Build a daily reading habit",
            title: "Build a Daily Reading Habit",
            questions: [
                "What type of reading are you focusing on?",
                "How many minutes per day do you want to read?",
                "Do you have a specific time of day in mind?",
                "Do you have books or reading material already lined up?",
                "What format do you prefer to read in?",
                "Have you tried building this habit before?",
                "What is your main motivation for reading more?"
            ],
            dimensions: ["type / focus", "scale (how much per day)", "schedule / time of day", "resources owned", "format / preferences", "past attempts", "motivation / goal"]
        ),
        GoldExemplar(
            input: "Start a side business selling ceramics",
            title: "Start a Ceramics Side Business",
            questions: [
                "Do you already make ceramics, or are you starting from scratch?",
                "What types of ceramics do you want to sell?",
                "Where do you plan to sell your ceramics?",
                "Do you have your own kiln and equipment, or do you use a shared studio?",
                "What is your budget to invest in getting started?",
                "How much time per week can you dedicate to this business?",
                "Do you have a target customer in mind?"
            ],
            dimensions: ["current state / starting point", "product / what specifically", "sales channel / location", "resources & equipment owned", "budget", "time available", "target audience / who-for"]
        ),
        GoldExemplar(
            input: "Set up a monthly household budget",
            title: "Set Up a Monthly Household Budget",
            questions: [
                "What is your total monthly household income after tax?",
                "How many people does this budget need to cover?",
                "Do you have a specific financial goal you want this budget to support?",
                "Which expense categories are most important to track for you?",
                "Do you already know your approximate monthly spending in key areas?",
                "What tool or format do you want to use for this budget?",
                "Have you had a household budget before that did not work out?"
            ],
            dimensions: ["income / resources", "scale / who-for (household size)", "goal", "priorities / focus areas", "current state known", "tool / format", "past attempts"]
        ),
        GoldExemplar(
            input: "Adopt a dog",
            title: "Adopt a Dog",
            questions: [
                "Do you have a specific breed in mind?",
                "What is your living situation like?",
                "Have you owned a dog before?",
                "What age of dog are you looking for?",
                "What is your budget for adoption and initial setup costs?",
                "Are there other people or pets in your household?",
                "What city or region are you located in?"
            ],
            dimensions: ["preferences (breed)", "living situation / context", "past experience", "specifics (age)", "budget", "household members / who-for", "location"]
        ),
        GoldExemplar(
            input: "Find a birthday gift for my dad",
            title: "Find a Birthday Gift for My Dad",
            questions: [
                "When is your dad's birthday?",
                "What is your budget for the gift?",
                "What are your dad's main hobbies or interests?",
                "How old is your dad turning?",
                "Do you prefer to buy online or in a physical store?",
                "Is this gift from you alone or from multiple people?",
                "Are there any gift types you want to avoid?"
            ],
            dimensions: ["timeline / deadline", "budget", "interests / preferences", "specifics (age)", "channel (where)", "who-for / from-whom", "things to avoid"]
        ),
        GoldExemplar(
            input: "Declutter my entire apartment",
            title: "Declutter My Entire Apartment",
            questions: [
                "How many rooms does your apartment have?",
                "What is driving you to declutter right now?",
                "Do you have a deadline you need to finish by?",
                "Which room or area feels most urgent to tackle first?",
                "What do you plan to do with items you no longer want?",
                "How much time can you realistically dedicate each day?",
                "Are you decluttering alone or will someone be helping you?"
            ],
            dimensions: ["scale (how much)", "motivation / why now", "timeline / deadline", "priority / where to start", "disposal plan / outcome", "time available", "alone vs help"]
        ),
        GoldExemplar(
            input: "Start meal prepping for the week",
            title: "Start Meal Prepping for the Week",
            questions: [
                "Which meals are you prepping for during the week?",
                "How many people are you cooking for?",
                "Do you follow any specific diet or have dietary restrictions?",
                "What day of the week do you want to do your prep?",
                "How much time can you realistically set aside for prepping?",
                "What is your weekly grocery budget for meals?",
                "What is your current cooking skill level?"
            ],
            dimensions: ["scope (which meals)", "scale / who-for", "dietary restrictions / constraints", "schedule / timing", "time available", "budget", "current skill level"]
        ),
        GoldExemplar(
            input: "Quit smoking",
            title: "Quit Smoking",
            questions: [
                "When do you want to quit by?",
                "How many cigarettes do you smoke per day?",
                "How long have you been smoking?",
                "Have you tried to quit before?",
                "What is your biggest trigger for smoking?",
                "Are you open to using quitting aids?",
                "Do you want professional support as part of your plan?"
            ],
            dimensions: ["timeline / deadline", "current state (how much)", "history / duration", "past attempts", "triggers / obstacles", "openness to aids / methods", "support needs"]
        ),
        GoldExemplar(
            input: "Write a best man speech",
            title: "Write a Best Man Speech",
            questions: [
                "What is the groom's name?",
                "What is your relationship to the groom?",
                "What is the bride's (or partner's) name?",
                "What tone do you want for the speech?",
                "Do you have a specific story or memory you want included?",
                "How long should the speech be?",
                "Is there anything you want to avoid mentioning?"
            ],
            dimensions: ["subject / who-for", "relationship / context", "key people involved", "tone / style", "specific content to include", "scale (length)", "things to avoid"]
        ),
    ]

    // MARK: - Retrieval

    /// Jaccard similarity on lowercased, punctuation-stripped word tokens.
    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0.0 : Double(inter) / Double(union)
    }

    private static func wordSet(_ s: String) -> Set<String> {
        // strip punctuation, lowercase, split on whitespace
        let stripped = s.unicodeScalars
            .filter { CharacterSet.letters.union(.whitespaces).contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
        return Set(stripped.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty })
    }

    /// Return the k exemplars whose input is most similar to the query (word overlap).
    /// `excludingInput`: if non-nil, drop any exemplar whose input matches it
    /// (case/whitespace-insensitive). Used for leave-one-out retrieval so that an
    /// eval case never receives its OWN gold question-set as a demonstration — the
    /// non-leaking version of RAG few-shot now that the exemplar bank overlaps the
    /// full-30 gate (EXP-033).
    static func nearest(to query: String, k: Int, excludingInput excluded: String? = nil) -> [GoldExemplar] {
        let qWords = wordSet(query)
        let norm: (String) -> String = { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let ex = excluded.map(norm)
        return all
            .filter { ex == nil || norm($0.input) != ex! }
            .map { e in (e, jaccard(qWords, wordSet(e.input))) }
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { $0.0 }
    }

    /// EXP-007: semantic nearest via on-device NLEmbedding (cosine), with the
    /// word-overlap `nearest` as fallback when embeddings are unavailable.
    static func nearestSemantic(to query: String, k: Int) -> [GoldExemplar] {
        SemanticRetrieval.nearest(query: query, candidates: all, k: k,
                                  fallback: { q, kk in nearest(to: q, k: kk) })
    }

    /// EXP-006: task-conditioned coverage checklist. Aggregate the dimension labels
    /// from the k nearest exemplars, dedup case-insensitively while preserving first
    /// occurrence order. These are the decision-critical dimensions that strong sets
    /// probe for THIS task TYPE — retrieved, not a universal hard-coded list.
    static func coverageDimensions(to query: String, k: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for ex in nearest(to: query, k: k) {
            for d in ex.dimensions {
                let key = d.lowercased()
                if seen.insert(key).inserted { out.append(d) }
            }
        }
        return out
    }
}
