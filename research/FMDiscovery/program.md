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

- **exp007 ragFewShotSemantic** — quality **0.273** (dev), spec 100%, 0/0/10. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 3. **DISCARDED** (−0.047 vs exp003 best 0.320; also lost exp003's lone learn_guitar tie). Replaced exp003's word-overlap Jaccard exemplar retrieval with on-device NLEmbedding sentence-embedding cosine, so the 2 few-shot demonstrations are the nearest task TYPE even with zero shared vocabulary (resume↔interview, tax↔budget). Hypothesis was that exp003's win came from well-matched exemplars and that Jaccard's ~0 matches on topically distinct dev queries were leaving quality on the table. **Falsified.** Better-matched exemplars did NOT improve coverage — it stayed flat at 3, and the same failure modes recur verbatim (misses budget/departure-city/who-for, treats tax as document-filing, asks "do you have a budget?" instead of "what is your budget?", produces near-duplicate date pairs in wedding/trip). The 3B does not *transfer* an exemplar's decision-critical unknowns even when the exemplar is a closer semantic match; it imitates surface form, not which-unknowns-matter judgment. So exp003's edge was NOT about exemplar topical relevance (and swapping retrieval slightly hurt, plausibly because semantically-nearest≠most-instructive, e.g. a finance exemplar for tax steered toward generic money questions). Confirms again: retrieval/prompt-quality levers don't move the coverage wall. The remaining untried levers are the heavier ones the log keeps pointing to — forcing the model to keep/adapt N specific concrete gold questions as hard constraints, or distillation/adapter — not anything that merely changes what context we show a single FM call.

- **exp006 ragCoverageScaffold** — quality **0.290** (dev), spec 100%, 0/1/9. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 3. **DISCARDED** (−0.030 vs exp003 best 0.320). Tagged each gold question with a short decision-critical dimension label; at runtime aggregated the dimensions from the SAME 2 nearest exemplars exp003 retrieves and injected them as an explicit, adaptable, task-conditioned coverage checklist in a single call (no auditor). Insight: a RETRIEVED checklist is no better than a universal one — coverage stayed 3 and the headline dropped. The 3B treats abstract dimension labels ("budget", "scale", "things to avoid") as slot-fillers and turns them into VAGUE catch-all or COMPOUND questions: it rendered "scale"→generic "how many" re-asks, bundled labels into double-barreled asks (wedding "date AND time", "started planning AND hired vendors"), produced near-duplicate pairs (tax filed-vs-received), and even repeated "deadlines or deadlines". Naming the dimension does not give the 3B the judgment to (a) pick which dimension is most critical for THIS task or (b) phrase it atomically — it just adds an extra surface to over-fit. Both exp005 (universal checklist) and exp006 (retrieved checklist) confirm: explicit dimension menus, universal OR task-conditioned, do NOT fix coverage. The 3B needs the actual decision-critical QUESTION modeled, not a label — pointing toward injecting concrete retrieved exemplar questions as harder constraints (e.g. require it to keep/adapt N specific gold questions), or distillation/adapter, rather than any checklist scaffold.

- **exp005 ragCritiqueRevise** — quality **0.315** (dev), spec 100%, 0/1/9. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 3. **DISCARDED** (−0.005 vs exp003 best 0.320). Reflexion editor on the RAG draft: stage-1 = exp003, stage-2 = a 2nd FM auditor given the draft + a decision-critical checklist (budget/who-for/timeline/scale/location/current-state/goal), told to delete already-given/low-value/compound questions and fill the highest-value missing unknown, keeping strong questions verbatim. Insight: a hard universal checklist BACKFIRES on coverage — the auditor mechanically injected budget+timeline into tasks where they're noise (bakery naming got budget+timeline slots; gp_appointment got an irrelevant budget Q; tax got "storage budgets"), and the 3B can't tell which checklist dimensions are task-appropriate. It also introduced new redundancy (overlapping reworded pairs) and a literal "deadlines or deadlines" repetition. The editor neither reliably dropped the *right* given facts nor added the *right* missing unknown; it just swapped one set of wrong slots for another. Coverage stayed 3. Self-critique still can't supply the task-type judgment the 3B lacks; the checklist must be task-conditioned (retrieved per task type), not universal — pointing back toward richer RAG/distillation rather than reflexion.

- **exp004 ragCoverageBestOfN** — quality **0.245** (dev), spec 90% (1 error), 0/0/9. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 3. **DISCARDED** (−0.075 vs exp003 best; −0.062 vs baseline). Sampled 4 RAG sets at temps [0.3,0.6,0.9,1.0] and selected the best by a deterministic Swift coverage scorer (weighted dimension span: budget/timeline/scale/location/current-state high, redundancy + "how many"-already-stated penalties). Insight: best-of-N on a coverage-only ruler BACKFIRES — high-temp samples degrade atomicity (compound/parenthetical questions: dinner_party bundled budget+dietary, trip_paris parenthetical sub-asks → spec error) and specificity (tax got generic US W-2/1099 framing), and a keyword-coverage scorer can't see those and selects the worse set. Coverage did NOT improve (still 3). A useful ruler must score atomicity+specificity+task-fit, not just dimension keyword presence; and sampling noise needs a low-temp floor. Coverage gap remains the wall; selection-by-proxy on the 3B's own outputs is insufficient.

- **exp003 ragFewShot** — quality **0.320** (dev), spec 100%, 0/1/9. Rubric: atom 4, spec 3, cover 3, nat 3, nonRed 4. **NEW BEST** (+0.013 vs baseline). Hard-coded 12 non-dev gold exemplars; at runtime retrieve 2 nearest by word-overlap Jaccard, inject as few-shot demonstrations in system prompt, single FM call. Non-redundancy improved 3→4; first tie vs gold (learn_guitar). Judge notes show model still makes catastrophic errors (asks "What is the name of your bakery?" for a naming task; asks redundant scheduling questions for GP appointment); critical coverage gaps persist (budget, departure city, group size). The RAG scaffolding helped non-redundancy but the 3B still can't reliably reason about which unknowns are most decision-critical.

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
