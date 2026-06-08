import FoundationModels
import Contract

/// On-device guided-generation shape for the split. Mirrors `RambleResult`.
@Generable
struct FMRambleSplit {
    @Guide(description: "Each distinct, actionable task the user wants to do, as a short one-liner in their own terms (around 4-9 words). Empty if the input contains no actionable task. One intention = one task; never duplicate; never invent a task that is not in the input.")
    var tasks: [String]

    func toContract() -> RambleResult { RambleResult(tasks: tasks) }
}

/// Reasoning-first variant: the model must first surface the non-actionable
/// material (venting, musing, vague wishes, retractions) and explicitly decide
/// whether any concrete task remains, BEFORE listing tasks. The gate is enforced
/// deterministically in `toContract()`. Directly attacks the zero-task failures.
@Generable
struct FMRambleSplitReasoned {
    @Guide(description: "One or two sentences. Identify any material that is NOT a task: venting/emotion, idle musing, vague wishes or aspirations ('it would be nice to...', 'I keep daydreaming about...'), and anything the user retracted ('scratch that', 'never mind', 'actually no'). Then say whether any concrete action the user actually intends to DO remains.")
    var analysis: String

    @Guide(description: "true ONLY if the input contains at least one concrete action the user actually wants to do. false for pure venting, idle musing, vague wishes/aspirations, or when everything actionable was retracted.")
    var hasActionableTasks: Bool

    @Guide(description: "The distinct actionable tasks, each a short one-liner (around 4-9 words) in the user's own terms. MUST be empty if hasActionableTasks is false. One intention = one task; never duplicate; never invent; exclude anything the user retracted.")
    var tasks: [String]

    func toContract() -> RambleResult {
        RambleResult(tasks: hasActionableTasks ? tasks : [])
    }
}

/// Coverage-first variant: keeps the zero-task gate, but adds an exhaustive
/// over-generate step. Before the final list, the model must enumerate EVERY
/// distinct thing the user wants to do across the WHOLE ramble — including
/// intentions buried mid-sentence or returned to after a digression — so that
/// interleaved many-task rambles don't lose items to linear reading. The final
/// `tasks` field then dedups those candidates. Attacks the recall/coverage gap.
@Generable
struct FMRambleSplitCoverage {
    @Guide(description: "One or two sentences. Identify any material that is NOT a task: venting/emotion, idle musing, vague wishes or aspirations ('it would be nice to...', 'I keep daydreaming about...'), and anything the user retracted ('scratch that', 'never mind', 'actually no'). Then say whether any concrete action the user actually intends to DO remains.")
    var analysis: String

    @Guide(description: "true ONLY if the input contains at least one concrete action the user actually wants to do. false for pure venting, idle musing, vague wishes/aspirations, or when everything actionable was retracted.")
    var hasActionableTasks: Bool

    @Guide(description: "Scan the ENTIRE input from start to finish and list EVERY distinct action the user wants to do, in order of appearance — including any mentioned only briefly, buried mid-sentence, or returned to after the user digressed and jumped back to an earlier thought. Be exhaustive here: it is better to over-list now and merge duplicates in the next field. Exclude retracted items and pure venting/musing. Empty if hasActionableTasks is false.")
    var candidateIntentions: [String]

    @Guide(description: "The final distinct actionable tasks, each a short one-liner (around 4-9 words) in the user's own terms. Take candidateIntentions and merge ones that refer to the same intention into a single task; keep every genuinely distinct one. MUST be empty if hasActionableTasks is false. Never invent; exclude anything the user retracted.")
    var tasks: [String]

    func toContract() -> RambleResult {
        RambleResult(tasks: hasActionableTasks ? tasks : [])
    }
}
