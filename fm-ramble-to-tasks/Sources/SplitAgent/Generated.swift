import FoundationModels
import Contract

/// On-device guided-generation shape for the split. Mirrors `RambleResult`.
@Generable
struct FMRambleSplit {
    @Guide(description: "Each distinct, actionable task the user wants to do, as a short one-liner in their own terms (around 4-9 words). Empty if the input contains no actionable task. One intention = one task; never duplicate; never invent a task that is not in the input.")
    var tasks: [String]

    func toContract() -> RambleResult { RambleResult(tasks: tasks) }
}
