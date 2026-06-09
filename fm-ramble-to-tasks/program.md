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
- prog001 reasoning-first zero-task gate (singleShotReasoned, greedy) from baseline — fitness 0.691 (full), NEW BEST (first program), zero-task gate works (100% correct empties, precision 0.926); confirmed gaps now = PHRASING (2/5, terse all-lowercase fragments dropping detail like "with the post office"/"before Thursday") and recall on interleaved many-task rambles (missed buried prerequisites). Pairwise 0 win / 5 tie / 17 loss.
