# program.md — FM Discovery Autoresearch

Standing instructions + experiment log for an autoresearch loop (after
karpathy/autoresearch) whose goal is to make Apple's **on-device Foundation
Model** produce discovery questions that match Anthropic **claude-sonnet-4-6**
on both technical spec and quality — with no Anthropic access in production.

## The problem

Tada's discovery planner turns a one-liner ("plan a trip to Paris") into a
`DiscoveryResult`: a restated task title + summary + **exactly 7 atomic
clarifying questions**, each with a `requiresExternalAction` flag. Sonnet does
this well from a ~70-line prompt. The on-device 3B model, prompted single-shot,
does not — prior attempts passed structural evals but felt dumb in real use,
because the evals measured *shape*, not *judgment*, and the judge was itself a
weak local model.

## The setup (Karpathy mapping)

- **Immutable harness** (`Sources/EvalBench`, `gold/`) — the ruler. ~30 gold
  cases (input → Sonnet output), a deterministic **spec gate**, an **Anthropic
  judge** (pairwise-vs-gold + 1-5 rubric), and a **metric**. Do NOT edit during
  the loop; editing the ruler invalidates comparisons.
- **Mutable artifact** (`Sources/DiscoveryAgent`) — the thing we iterate.
  Free to use: better prompts, multi-call pipelines, recursion/self-critique,
  tool calls, retrieval/embeddings, adapters. Speed does not matter.
- **This file** — methodology + the experiment journal below.

## The metric

Per case: spec gate must pass (hard gate → quality 0 if it fails). Quality =
`0.5 * rubricNormalized + 0.5 * pairwiseScore`, where rubric is the mean of five
1-5 scores (atomicity, specificity, coverage, naturalness, non-redundancy)
normalized to 0-1, and pairwise maps {goldBetter:0, tie:0.5, fmBetter:1}.
Headline = mean quality over all cases. Also report: spec-pass rate, win/tie/
loss vs gold, per-dimension rubric means.

## The loop

1. Form ONE hypothesis about why the agent underperforms (read judge notes).
2. Edit only `Sources/DiscoveryAgent`. Keep the diff small and reviewable.
3. Run `swift run fmresearch evaluate` over all gold cases.
4. Compare headline metric to the current best. Keep if better, revert if not.
5. Log the experiment below (hypothesis, change, metric, decision). Repeat.

## Commands

- `swift run fmresearch availability` — check on-device model is available.
- `swift run fmresearch gold` — (re)generate gold outputs from Sonnet. Needs key.
- `swift run fmresearch evaluate` — run current agent over gold, judge, score.

Requires `ANTHROPIC_API_KEY` in the environment for `gold` and `evaluate`.

## Experiment log

_(newest first; quality on dev-10 proxy unless noted)_

- **PIVOT (after EXP-002):** Both structural moves lost to single-shot on the
  dev proxy. exp002 improved non-redundancy (3→4 via score+select-in-Swift) but
  collapsed coverage (3→2); pipelines also hurt naturalness (3rd-person phrasing).
  Judge notes are unanimous across configs: the gap is **coverage** — the 3B
  can't reliably identify the most decision-critical unknown per task type.
  Instructions/topology don't move it. Pivoting to distillation levers:
  (6) retrieval-augmented few-shot from the gold bank, then (7) adapter. This
  matches the prior real-world finding that prompt/pipeline tweaks were not
  sufficient. Best so far: **baseline 0.307**.

- **EXP-002 overGenerateScore** (dev) — quality **0.263**, spec 100%, 0/0/10.
  Rubric: atom 5, spec 3, cover 2, nat 3, nonRed 4. One call → 12 scored
  candidates → top-7 by importance in Swift. Non-redundancy best of all configs;
  coverage worst — importance scores rank niche features above critical unknowns.
- **EXP-001 brainstormSelect** (dev) — quality **0.235**, spec 90% (1 error),
  0/0/9. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 3. Two-stage; regressed
  vs single-shot, added robotic 3rd-person phrasing in the select stage.
- **baseline singleShot** (dev) — quality **0.307**, spec 100%, 0/1/9. Rubric:
  atom 5, spec 3, cover 3, nat 3, nonRed 3. (Full-30: 0.282, see EXP-000.)

- **EXP-001 dimension-scaffolded pipeline** — pending. Hypothesis: the gap is
  judgment (which 7 unknowns matter), not phrasing. Decompose into two FM calls
  the 3B can each handle: (1) brainstorm ~12 candidate unknowns against a
  universal planning-dimension scaffold (goal, who-for, scale, budget, timeline,
  location, current-state, resources-owned, constraints, channel, DIY-vs-help);
  (2) select the 7 most decision-relevant, drop redundant/filler/premature ones,
  phrase each as a natural atomic question. Target: beat 0.282; win/tie some.

- **EXP-000 baseline** — QUALITY **0.282**, spec pass 100%, vs gold **0 win /
  0 tie / 30 loss**. Rubric means: atomicity 4, specificity 3, coverage 3,
  naturalness 3, nonRedundancy 3. Single-shot Sonnet-prompt port. Sonnet wins
  every case. Judge-note failure patterns (results/EXP-000.json):
  (1) misses the single most critical unknown (coverage); (2) wastes slots on
  niche/premature detail; (3) redundant overlapping questions; (4) generic
  filler ("any concerns?"); (5) logical/off-target questions (bakery: "what's
  your business name?"); (6) robotic first-person phrasing. Atomicity is the one
  strong dimension — guided generation + the no-and/or rule hold.
