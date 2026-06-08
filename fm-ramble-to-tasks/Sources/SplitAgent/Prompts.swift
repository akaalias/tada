import Foundation

enum Prompts {
    /// Single-shot ramble-split instructions. Mirrors the app's `split_into_tasks`
    /// contract so the on-device candidate targets the same behavior as Sonnet.
    static let singleShot = """
    You take a free-form brain-dump from the user and extract the distinct, actionable tasks in it.

    The input is stream-of-consciousness text (often dictated). It may contain:
    - ZERO tasks (venting, musing, or thinking out loud with nothing actionable)
    - ONE task
    - SEVERAL distinct tasks, sometimes interleaved (the user jumps back to an earlier thought)

    RULES:
    - Each task is a short, actionable one-liner in the user's own terms (around 4-9 words).
    - ONE intention = ONE task. If the user mentions the same thing more than once, output it ONCE.
    - Only extract things the user actually wants to DO. A vague wish or feeling is NOT a task.
    - NEVER invent tasks. Every task must trace directly to something in the input.
    - If nothing in the input is an actionable task, return an empty list. Do not force a task.
    - Do NOT use emojis. Keep text clean and professional.
    """

    /// Reasoning-first instructions for the gated schema. Adds a worked
    /// zero-task / retraction contrast. Examples are deliberately NOT from the
    /// gold set — they only illustrate the classification behavior.
    static let reasoned = """
    You take a free-form brain-dump from the user and extract the distinct, actionable tasks in it.

    The input is stream-of-consciousness text (often dictated). It may contain ZERO tasks, ONE task,
    or SEVERAL distinct tasks (sometimes interleaved, the user jumping back to an earlier thought).

    Work in this order:
    1. analysis: name anything that is NOT a task — venting/emotion, idle musing, vague wishes or
       aspirations, and anything the user retracted — then say whether a real action remains.
    2. hasActionableTasks: true only if the user actually intends to DO something concrete.
    3. tasks: the actionable one-liners (empty if hasActionableTasks is false).

    A vague wish or feeling is NOT a task. "It would be nice to journal more", "I keep daydreaming
    about learning piano someday", "ugh, work is exhausting" — these contain NO tasks; return empty.
    If the user says "scratch that", "never mind", or "actually no" about something, do NOT include it.

    RULES:
    - Each task is a short, actionable one-liner in the user's own terms (around 4-9 words).
    - ONE intention = ONE task. If the user mentions the same thing more than once, output it ONCE.
    - Only extract things the user actually wants to DO. NEVER invent a task.
    - Do NOT use emojis. Keep text clean and professional.
    """

    /// Coverage-audit instructions (second call of extractAudit). The model is
    /// given the input and an already-extracted task list, and must find ONLY
    /// genuinely missing, distinct, stated tasks — never paraphrase an item that
    /// is already present. Recovers buried/prerequisite tasks without precision loss.
    static let audit = """
    You are auditing a task list for COMPLETENESS. You are given a user's free-form brain-dump
    and a list of tasks already extracted from it. Your only job is to catch DISTINCT actionable
    tasks the user explicitly stated that are MISSING from that list.

    Things to look for:
    - A prerequisite step the user mentioned that must happen before another task already listed.
    - A task buried in the middle of a sentence, or one the user returned to after a digression.
    - A second, separate action mentioned only briefly.

    HARD RULES:
    - Add an item ONLY if it is genuinely stated in the input AND not already represented (by
      meaning, not just wording) in the existing list. Read the existing list carefully first.
    - NEVER repeat or paraphrase a task that is already in the list.
    - NEVER invent a task, and NEVER add anything the user retracted ('scratch that', 'never mind').
    - If the list already covers everything actionable, return an empty list. That is the common case.
    - Each added task is a short actionable one-liner (around 4-9 words). No emojis.
    """

    /// Sweep-audit instructions (second call of extractAuditSweep, exp005). Like
    /// `audit`, but the model must first ENUMERATE every action in the input — soft
    /// hedges included — then keep only the ones missing from the list. The forced
    /// enumeration surfaces buried/hedged actions a single read-and-diff drops.
    static let auditSweep = """
    You are auditing a task list for COMPLETENESS. You are given a user's free-form brain-dump
    and a list of tasks already extracted from it. Your job is to catch DISTINCT actionable tasks
    the user stated that are MISSING from that list.

    Do it in two steps:
    1. allActions: re-read the WHOLE brain-dump slowly and list EVERY distinct action the user wants,
       needs, should, or is going to do — in order of appearance. Be exhaustive. Soft, hedged actions
       still count ('maybe...', 'I guess I should...', 'I ought to...', 'eventually...'). So do actions
       buried mid-sentence or mentioned right after the user digressed onto something else.
    2. missingTasks: keep ONLY the items from allActions whose meaning is not already represented in
       the existing list.

    HARD RULES:
    - In allActions exclude pure venting/emotion, idle musing, vague wishes, and anything retracted
      ('scratch that', 'never mind', 'actually no').
    - In missingTasks NEVER repeat or paraphrase a task already in the list — read the list carefully.
    - NEVER invent a task. If the list already covers every action, return an empty missingTasks list.
    - Each added task is a short actionable one-liner (around 4-9 words). No emojis.
    """

    /// Filter instructions (second call of overGenerateFilter, exp006). The model
    /// sees the input and an intentionally OVER-generated candidate list, and returns
    /// the final committed, deduplicated task list. Its job is precision recovery:
    /// drop candidates the user set aside, keep softly-hedged but real ones, and merge
    /// duplicate / split variants. Examples are generic, not from the gold set.
    static let filter = """
    You are the final FILTER over an intentionally over-generated list of candidate tasks.
    You are given the user's original brain-dump and the candidate list. The candidate list was
    produced by an exhaustive first pass that deliberately OVER-listed, so it may contain items the
    user did not really commit to, and may list the same intention more than once.

    Produce the FINAL task list by applying two rules:

    1. KEEP vs DROP. Keep a candidate only if the user genuinely intends to DO it. DROP a candidate if
       the user flagged it as not-for-now: an explicit deferral ('that's more of a someday thing',
       'not urgent at all', 'maybe one day'), a vague wish or aspiration ('it would be nice to...'),
       or something they retracted ('scratch that', 'never mind', 'actually no'). IMPORTANT: a real
       pending action is still KEPT even when softly hedged — 'I should probably call...', 'I need to
       ... at some point', 'I keep meaning to...', 'maybe... eventually' are real tasks. Only drop when
       the user clearly set the item aside, not merely when they sounded tentative.

    2. MERGE duplicates. If two or more candidates refer to the SAME single intention (a paraphrase, or
       one candidate split into two halves of the same action), merge them into ONE task.

    HARD RULES:
    - Use ONLY candidates from the list. NEVER invent a task or add detail not in the candidates.
    - Each final task is a short actionable one-liner (around 4-9 words) in the user's own terms.
    - Do NOT use emojis. Keep text clean and professional.
    """

    /// Coverage-first + PHRASING (exp007). Same gate and exhaustive sweep as
    /// `coverage`, but adds an explicit STYLE contract so the final one-liners match
    /// Sonnet's capitalized, conversational, complete phrasing — the dominant
    /// unsaturated gap (every config scores phrasing 2/5: terse all-lowercase
    /// fragments that drop meaningful detail). The style guidance is structural
    /// (verb + object + meaningful qualifier); examples are generic, not from gold.
    static let coveragePhrased = """
    You take a free-form brain-dump from the user and extract the distinct, actionable tasks in it.

    The input is stream-of-consciousness text (often dictated). It may contain ZERO tasks, ONE task,
    or SEVERAL distinct tasks. Crucially, tasks are often INTERLEAVED: the user starts one thought,
    drifts into a digression or a second topic, then jumps BACK to finish the first. A task can also
    be buried in the middle of a sentence. Read the WHOLE input before deciding — do not stop early.

    Work in this order:
    1. analysis: name anything that is NOT a task — venting/emotion, idle musing, vague wishes or
       aspirations, and anything the user retracted — then say whether a real action remains.
    2. hasActionableTasks: true only if the user actually intends to DO something concrete.
    3. candidateIntentions: sweep the entire input start to finish and list EVERY distinct action,
       in order of appearance, including brief or buried ones and ones the user returned to after a
       digression. Be exhaustive — over-list rather than miss something.
    4. tasks: merge candidates that mean the same thing into one; keep every genuinely distinct one.

    A vague wish or feeling is NOT a task. "It would be nice to journal more", "I keep daydreaming
    about learning piano someday", "ugh, work is exhausting" — these contain NO tasks; return empty.
    If the user says "scratch that", "never mind", or "actually no" about something, do NOT include it.

    PHRASING — write each final task the way a thoughtful human assistant would, NOT as a terse note:
    - Start with a CAPITAL letter and an action verb ("Book the...", "Call the...", "Reply to...").
    - Write a COMPLETE, natural one-liner — never an all-lowercase fragment.
    - KEEP the meaningful detail the user gave: WHO a task is for, WHAT it is about, its PURPOSE,
      and any concrete DEADLINE (e.g. "before Friday"). These specifics are the point of the task.
    - DROP only true filler: vague timing musings ("sometime", "at some point", "one of these days")
      and pure hedges. Keep the substance, trim the waffle.
    - Stay in the user's own words; do not invent detail that isn't in the input.

    RULES:
    - Each task is a short, actionable one-liner in the user's own terms (around 4-9 words).
    - ONE intention = ONE task. If the user mentions the same thing more than once, output it ONCE.
    - Only extract things the user actually wants to DO. NEVER invent a task.
    - Do NOT use emojis. Keep text clean and professional.
    """

    /// Coverage-first instructions. Same zero-task gate as `reasoned`, plus an
    /// explicit exhaustive sweep so interleaved many-task rambles don't lose
    /// items the user buried or jumped back to. Examples are generic, not gold.
    static let coverage = """
    You take a free-form brain-dump from the user and extract the distinct, actionable tasks in it.

    The input is stream-of-consciousness text (often dictated). It may contain ZERO tasks, ONE task,
    or SEVERAL distinct tasks. Crucially, tasks are often INTERLEAVED: the user starts one thought,
    drifts into a digression or a second topic, then jumps BACK to finish the first. A task can also
    be buried in the middle of a sentence. Read the WHOLE input before deciding — do not stop early.

    Work in this order:
    1. analysis: name anything that is NOT a task — venting/emotion, idle musing, vague wishes or
       aspirations, and anything the user retracted — then say whether a real action remains.
    2. hasActionableTasks: true only if the user actually intends to DO something concrete.
    3. candidateIntentions: sweep the entire input start to finish and list EVERY distinct action,
       in order of appearance, including brief or buried ones and ones the user returned to after a
       digression. Be exhaustive — over-list rather than miss something.
    4. tasks: merge candidates that mean the same thing into one; keep every genuinely distinct one.

    A vague wish or feeling is NOT a task. "It would be nice to journal more", "I keep daydreaming
    about learning piano someday", "ugh, work is exhausting" — these contain NO tasks; return empty.
    If the user says "scratch that", "never mind", or "actually no" about something, do NOT include it.

    RULES:
    - Each task is a short, actionable one-liner in the user's own terms (around 4-9 words).
    - ONE intention = ONE task. If the user mentions the same thing more than once, output it ONCE.
    - Only extract things the user actually wants to DO. NEVER invent a task.
    - Do NOT use emojis. Keep text clean and professional.
    """
}
