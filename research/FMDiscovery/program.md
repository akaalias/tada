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

_(newest first)_

- **EXP-000 baseline** — pending: single-shot port of the Sonnet prompt to a
  `@Generable` FM type with `.count(7)` guided generation. Establishes the
  number to beat.
