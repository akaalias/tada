# fm-ramble-to-tasks — experiment log

Newest first. One line per experiment. The autonomous agent prepends here each run.

**Current best:** `exp001` — singleShotReasoned, greedy, stock FM — **DEV 0.955 / TEST 1.000** (held-out validated; zero-task 100% on both, incl. fresh bait the config never had examples for).

You are scored on the DEV split. The TEST split is held out — never tune toward it.

**State of the gap:**
- ZERO-TASK: SOLVED by exp001 (reasoning-first gate) and it GENERALIZES to held-out.
- The gold set is now near-saturated (exp001 ≈ ceiling). Until it grows harder/larger,
  only clear MULTI-case gains count — dev has 11 cases, one ≈ 0.09; ignore smaller wiggles.
- Residual headroom is on the hardest inputs: long, heavily-interleaved, many-task
  rambles where coverage/dedup are hardest. Prefer ideas that help THERE.

## Log
- exp002 coverage-first (gate + exhaustive candidateIntentions sweep before final list) — quality 0.943 (full), DISCARDED (−0.012 vs exp001 0.955, within noise). The over-generate sweep is a genuine trade: it fixed multi_errands (0.8→1.0, recovered the buried task) but caused dedup_groceries to emit a duplicate (precision 1.0→0.955), and interleaved_deck still drops its prerequisite. Pushing recall via in-schema over-listing costs dedup precision; net wash. Recall gains likely need a dedup pass that can't leak duplicates.
- [operator] re-seeded onto DEV/TEST splits + tightened the leak rule; held-out TEST (2 fresh bait cases unlike any prompt example) confirms exp001 GENERALIZES — DEV 0.955, TEST 1.000, zero-task 100% on both. The win is real, not memorized.
- exp001 reasoning-first gated schema (analysis + hasActionableTasks bool gate before tasks) — quality 0.967 (full), NEW BEST (+0.24 over baseline). Forcing the model to name venting/musing/retractions and commit a boolean before listing fixed all 4 zero-task cases (100% correct empties) and the long_portugal retraction; extraction cases unaffected.
- baseline — singleShot greedy on stock FM — quality 0.727 (full), seed baseline. Extraction cases ~1.0; entire gap is the 4 zero-task failures + one retraction.
