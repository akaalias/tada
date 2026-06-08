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
