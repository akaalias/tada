# fm-ramble-to-tasks — program log

Newest first. One line per program. The autonomous agent prepends here each run.

**Elite:** none yet — fresh start (zero programs). Build the first program
(`prog001`) from the stock `baseline` (single-shot, greedy).

You are scored on the DEV split. The TEST split is held out — never tune toward it.

**Metric:** fitness = 0.5·F1 + 0.25·rubric + 0.25·pairwise (zero-task cases scored binary).
The rubric includes PHRASING. Gold: 35 cases (27 dev / 8 test).

**State of the gap (to be discovered — nothing run yet):**
- ZERO-TASK is the known #1 failure mode — do NOT invent tasks on non-actionable input
  (venting / musing / retractions); an empty list is the correct answer.
- PHRASING is expected to be the hard part: match Sonnet's capitalized, conversational,
  complete style (keep detail) rather than terse all-lowercase fragments — without losing F1.

## Log
- prog002 elite reasoned extract + decoupled F1-safe verbatim restyle finisher (downcase+recase+completeness prompt) from prog001 — fitness 0.710 (full), NEW BEST (marginal, +0.019 within noise but every signal coherent): phrasing 2→3, pairwise 5T/17L→8T/13L, F1 flat 0.877 (set membership preserved by 1:1 guard, as designed). Residual: the token-subset guard still REJECTS many fuller restyles back to terse base (drops "with the post office"/"about the kitchen sink"), so completeness under-fires — next lever is loosening the guard for input-verbatim detail without re-opening hallucination. Minor: one restyle attached input-present detail to the wrong task (interleaved_deck), F1 unaffected.
- prog001 reasoning-first zero-task gate (singleShotReasoned, greedy) from baseline — fitness 0.691 (full), NEW BEST (first program), zero-task gate works (100% correct empties, precision 0.926); confirmed gaps now = PHRASING (2/5, terse all-lowercase fragments dropping detail like "with the post office"/"before Thursday") and recall on interleaved many-task rambles (missed buried prerequisites). Pairwise 0 win / 5 tie / 17 loss.
