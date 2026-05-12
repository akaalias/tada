# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## 5. No Thinking Loops — Commit or Stop

**Once you've done recon and stated a plan, EXECUTE. No re-stating.**

The loop pattern: "Now I'm mapping out changes" → repeat 10x with identical content.

**Rule:** After stating a plan, the very next action MUST be a tool call (edit/write/bash). No more analysis paragraphs. No re-stating the same approach.

### Anti-loop mechanism (HARD RULE)
- State plan ONCE in a single paragraph (max 5 bullet points). That's it. One time only.
- Immediately start executing with tool calls (edit/write/bash).
- **Verification commands (`ls`, `cat`, file reads) are PART of execution, not analysis.** After any command returns — even if it's just confirming a file exists — you EXECUTE. You do NOT restate the plan.
- **The forbidden pattern:** state plan → run `ls`/read file → restate plan → run same `ls`/read file → repeat. This is a failure state.
- **If you find yourself about to restate the plan:** write the first file immediately. No preamble. No "now I'll..." Just a tool call.
- **Self-correction trigger:** If your next response starts with "Now I have a good understanding" or "Let me create..." after already stating the plan — you're looping. Stop talking, start writing.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions come before implementation rather than after mistakes, and zero thinking-loop repetitions.

## 6. Get Caught Up On Previous Work
- At the start of a new session, read [[CONTEXT.md]]
- If there is any pending work to do, mention it to the user

## 7. TDD Workflow — Test First, Always

**Write the test that should fail first. Then make it pass. Then refactor.**

For every feature or bugfix, follow this cycle:

1. **Write the test** — Describe the desired behavior as a failing test (UI or unit). Be specific about inputs, outputs, and edge cases.
2. **Watch it fail** — Confirm the test actually fails for the right reason (red).
3. **Implement production code** — Write the minimum code to make the test pass (green).
4. **Refactor** — Clean up both test and production code while keeping all tests green.

Rules:
- Never write production code without a failing test first.
- Tests describe *what* the system should do. Production code describes *how*.
- If a test can't fail, it's not a real test — rewrite it.
- Keep tests fast and focused. One assertion per test when possible.
- For UI features, write the Cypress/E2E test first. For logic, write the unit test first.

This isn't dogma — it's a discipline that catches regressions early and keeps design decisions grounded in actual requirements. 
