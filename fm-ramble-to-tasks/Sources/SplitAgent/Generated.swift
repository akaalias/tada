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

/// Coverage-audit pass (second call of the extractAudit topology). Given the
/// input AND the tasks already extracted, it surfaces ONLY distinct actionable
/// intentions that are genuinely STATED in the input but MISSING from that list
/// (e.g. a prerequisite step, or a task buried mid-sentence / returned to after a
/// digression). Because it can see the committed list, it won't re-add a
/// paraphrase of an item already present — the failure mode that sank exp002.
@Generable
struct FMRambleAudit {
    @Guide(description: "One sentence. Re-read the WHOLE input and the already-extracted list. Name any distinct action the user explicitly wants to DO that is STATED in the input but is NOT yet represented (by meaning) in that list — e.g. a prerequisite step, or a task buried mid-sentence or returned to after a digression. If the list already covers everything, say so.")
    var omissionCheck: String

    @Guide(description: "ONLY the distinct actionable tasks that are stated in the input but MISSING from the already-extracted list. Each a short one-liner (around 4-9 words) in the user's own terms. Do NOT repeat or paraphrase anything already in the list. Do NOT invent. Empty if the list is already complete.")
    var missingTasks: [String]
}

/// Sweep variant of the coverage-audit (exp005). Same job as FMRambleAudit, but
/// instead of reading the input once and naming the gap, it first ENUMERATES every
/// action in the input (including softly-hedged ones), THEN diffs that enumeration
/// against the committed list. The forced sweep surfaces buried / hedged actions
/// that a single read-and-diff drops (exp004's residual: a hedged task buried among
/// digressions in a long many-task ramble). Still gated to base>=2.
@Generable
struct FMRambleAuditSweep {
    @Guide(description: "Re-read the WHOLE input slowly, start to finish, and list EVERY distinct action the user says they want, need, should, or are going to DO — in order of appearance. Be exhaustive: include SOFTLY-HEDGED ones (phrased with 'maybe', 'I guess I should', 'I ought to', 'eventually') and any buried mid-sentence or mentioned right after a digression. Exclude ONLY pure venting, idle musing, vague wishes, and retracted items.")
    var allActions: [String]

    @Guide(description: "ONLY the items from allActions whose meaning is NOT already represented in the already-extracted list. Each a short one-liner (around 4-9 words) in the user's own terms. Do NOT repeat or paraphrase anything already in the list. Do NOT invent. Empty if the list already covers every action.")
    var missingTasks: [String]
}

/// Filter pass (second call of the overGenerateFilter topology, exp006). Given the
/// input AND an intentionally OVER-generated candidate list, it returns the final
/// task list: keeping only candidates the user genuinely commits to (dropping ones
/// flagged as someday / not urgent / vague wish / retracted) and merging duplicate
/// or split variants of the same intention into one. This is where precision is
/// recovered after the over-generate pass deliberately sacrificed it — it must
/// separate a kept softly-hedged-but-pending action from a dropped explicit deferral.
@Generable
struct FMRambleFilter {
    @Guide(description: "One sentence. For the candidate list, note which items the user genuinely commits to doing versus which they flagged as NOT now — someday / not urgent / a vague wish or aspiration / retracted ('never mind') — and which candidates are duplicates or split halves of the SAME single intention. A softly-hedged but real pending action ('I should probably...', 'I need to... at some point', 'maybe... eventually') is KEPT; an explicit deferral the user set aside ('that's more of a someday thing, not urgent') is dropped.")
    var review: String

    @Guide(description: "The FINAL distinct actionable tasks, each a short one-liner (around 4-9 words) in the user's own terms. Keep ONLY candidates the user genuinely commits to doing; drop candidates flagged as someday / not urgent / a vague wish / retracted. Merge any duplicates or split variants of the same intention into ONE task. Use only candidates from the list — never invent.")
    var finalTasks: [String]
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

/// Style-only rewrite pass (second call of singleShotCoverageRestyle, exp008).
/// Given the original input AND the already-extracted task list, it REWRITES each
/// task in Sonnet's capitalized, complete, conversational style — restoring
/// meaningful detail the terse extractor dropped (purpose / recipient / subject /
/// deadline, recoverable from the input) — WITHOUT changing the set of tasks. It
/// must return EXACTLY one styled task per input task, in the SAME order. The
/// agent enforces this 1:1 mapping deterministically (count-mismatch -> keep the
/// base list), so this pass can lift the phrasing rubric but can NEVER change F1.
@Generable
struct FMRambleRestyle {
    @Guide(description: "Rewrite each task from the given list, IN THE SAME ORDER, returning EXACTLY one rewritten task per input task — never add, drop, split, merge, or reorder. For each task, keep its exact MEANING but rephrase it the way a thoughtful human assistant would write a to-do: start with a CAPITAL letter and an action verb, write a COMPLETE natural one-liner (never an all-lowercase fragment), and restore the meaningful detail the user gave that a terse note would drop — who it is for, what it is about, its purpose, and any concrete deadline (use the original brain-dump to recover that detail). Drop only true filler (vague timing like 'sometime', 'at some point'). Around 4-9 words. Never invent detail that is not in the input.")
    var styled: [String]
}

/// Verbatim-detail restyle pass (second call of singleShotCoverageRestyleVerbatim,
/// exp010). Same 1:1 style-only contract as FMRambleRestyle, but the guide stresses
/// that any restored detail must be copied from the user's EXACT words. exp009's
/// anti-hallucination guard rejects a restyle on any content word not present in the
/// input, so paraphrased detail gets the whole task thrown back to its terse base;
/// pulling the detail verbatim keeps the restyle inside the guard so genuine
/// completeness restores actually survive.
@Generable
struct FMRambleRestyleVerbatim {
    @Guide(description: "Rewrite each task from the given list, IN THE SAME ORDER, returning EXACTLY one rewritten task per input task — never add, drop, split, merge, or reorder. For each task: start with a CAPITAL letter and an action verb, write a COMPLETE natural one-liner (never an all-lowercase fragment), and RE-ATTACH the meaningful detail a terse note dropped — the deadline, the subject the task is about, the recipient it is for, and the location. CRITICAL: copy that detail using the user's OWN EXACT WORDS from the brain-dump — do not paraphrase it and do not invent any word that is not in the input. Drop only true filler ('sometime', 'at some point'). Around 4-9 words.")
    var styled: [String]
}

/// Coverage-first + PHRASING variant (exp007). Identical pipeline to
/// FMRambleSplitCoverage (analysis gate -> exhaustive candidate sweep -> merged
/// final list), but the final `tasks` @Guide carries an explicit STYLE contract so
/// the one-liners match Sonnet's capitalized, conversational, complete phrasing.
/// This attacks the dominant unsaturated gap: every prior config scores phrasing
/// 2/5 because the on-device model emits terse all-lowercase fragments that drop
/// meaningful detail (purpose / recipient / subject / deadline).
@Generable
struct FMRambleSplitCoveragePhrased {
    @Guide(description: "One or two sentences. Identify any material that is NOT a task: venting/emotion, idle musing, vague wishes or aspirations ('it would be nice to...', 'I keep daydreaming about...'), and anything the user retracted ('scratch that', 'never mind', 'actually no'). Then say whether any concrete action the user actually intends to DO remains.")
    var analysis: String

    @Guide(description: "true ONLY if the input contains at least one concrete action the user actually wants to do. false for pure venting, idle musing, vague wishes/aspirations, or when everything actionable was retracted.")
    var hasActionableTasks: Bool

    @Guide(description: "Scan the ENTIRE input from start to finish and list EVERY distinct action the user wants to do, in order of appearance — including any mentioned only briefly, buried mid-sentence, or returned to after the user digressed and jumped back to an earlier thought. Be exhaustive here: it is better to over-list now and merge duplicates in the next field. Exclude retracted items and pure venting/musing. Empty if hasActionableTasks is false.")
    var candidateIntentions: [String]

    @Guide(description: "The final distinct actionable tasks. Merge candidateIntentions that mean the same thing into one; keep every genuinely distinct one. PHRASE each task the way a thoughtful human assistant would write it: start with a CAPITAL letter and an action verb, write a COMPLETE natural one-liner (never an all-lowercase fragment), and KEEP the meaningful detail the user gave — who it is for, what it is about, its purpose, and any concrete deadline. DROP only vague filler timing ('sometime', 'at some point') and pure hedges. Around 4-9 words, in the user's own words. MUST be empty if hasActionableTasks is false. Never invent detail not in the input; exclude anything retracted.")
    var tasks: [String]

    func toContract() -> RambleResult {
        RambleResult(tasks: hasActionableTasks ? tasks : [])
    }
}
