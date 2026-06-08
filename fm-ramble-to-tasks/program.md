# fm-ramble-to-tasks — experiment log

Newest first. One line per experiment. The autonomous agent prepends here each run.

**Current best:** `exp001` — singleShotReasoned, greedy, stock FM — quality **0.967** (full set).

**Dominant gap to attack:**
- ZERO-TASK (#1 lever): all 4 venting/bait cases score 0.000 — the stock FM invents
  tasks on non-actionable input. Make it return `[]` when nothing is actionable.
- RETRACTION: long_portugal kept a "scratch that" task (faithfulness miss).
Faithfulness and coverage are the load-bearing rubric dimensions.

## Log
- exp001 reasoning-first gated schema (analysis + hasActionableTasks bool gate before tasks) — quality 0.967 (full), NEW BEST (+0.24 over baseline). Forcing the model to name venting/musing/retractions and commit a boolean before listing fixed all 4 zero-task cases (100% correct empties) and the long_portugal retraction; extraction cases unaffected.
- baseline — singleShot greedy on stock FM — quality 0.727 (full), seed baseline. Extraction cases ~1.0; entire gap is the 4 zero-task failures + one retraction.
