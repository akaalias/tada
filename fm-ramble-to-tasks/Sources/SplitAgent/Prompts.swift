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
}
