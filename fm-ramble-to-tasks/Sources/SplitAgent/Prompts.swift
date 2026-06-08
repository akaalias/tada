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
