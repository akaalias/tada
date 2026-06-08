# fm-ramble-to-tasks — experiment log

Newest first. One line per experiment. The autonomous agent prepends here each run.

**Current best:** `baseline` — singleShot, greedy, stock FM — quality **0.727** (full set).

**Dominant gap to attack:**
- ZERO-TASK (#1 lever): all 4 venting/bait cases score 0.000 — the stock FM invents
  tasks on non-actionable input. Make it return `[]` when nothing is actionable.
- RETRACTION: long_portugal kept a "scratch that" task (faithfulness miss).
Faithfulness and coverage are the load-bearing rubric dimensions.

## Log
- baseline — singleShot greedy on stock FM — quality 0.727 (full), seed baseline. Extraction cases ~1.0; entire gap is the 4 zero-task failures + one retraction.
