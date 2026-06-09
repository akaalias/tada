# fm-ramble-to-tasks — experiment log

Newest first. One line per experiment. The autonomous agent prepends here each run.

**Current best:** none yet — fresh start (zero experiments). Build the first experiment
(`exp001`) from the stock `baseline` (single-shot, greedy).

You are scored on the DEV split. The TEST split is held out — never tune toward it.

**Metric:** quality = 0.5·F1 + 0.25·rubric + 0.25·pairwise (zero-task cases scored binary).
The rubric includes PHRASING. Gold: 35 cases (27 dev / 8 test).

**State of the gap (to be discovered — nothing run yet):**
- ZERO-TASK is the known #1 failure mode — do NOT invent tasks on non-actionable input
  (venting / musing / retractions); an empty list is the correct answer.
- PHRASING is expected to be the hard part: match Sonnet's capitalized, conversational,
  complete style (keep detail) rather than terse all-lowercase fragments — without losing F1.

## Log
