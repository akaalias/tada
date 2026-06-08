# fm-ramble-to-tasks

Autoresearch project: find an on-device Apple Foundation Model configuration (stock
or `.fmadapter`) that turns a free-form user input into 0..N atomic, actionable tasks
as well as Sonnet 4.6 does.

This is the step *before* discovery. FMDiscovery turns one clean one-liner into 7
questions. This project turns a messy, stream-of-consciousness input (already
transcribed to text by something like Wisp Flow — we never touch audio) into the
0..N one-liners that feed discovery.

Branch: `research/fm-ramble-to-tasks`. Each research project lives in its own
top-level folder (not under `research/`).

---

## The task

Input: free-form text. Could contain zero, one, or many distinct intentions, possibly
interleaved (jumps back to an earlier thread) or buried in non-actionable rambling.

Output: `0..N` atomic, actionable task one-liners. `[]` is a valid, correct answer.

Policy decisions that *define* the task (these are fixed, not tunable):
- A single intention mentioned twice => ONE task (no duplicates).
- Vague musing ("someday I'd love to learn piano") => NOT a task.
- Faithfulness: every task must trace to the input. No invented tasks.

---

## Sequencing — app feature FIRST

The Sonnet behavior in the app *is* the gold the research loop tries to match. So we
build the production feature before the research infra.

1. **App feature (production, Sonnet):** in the tada app, take whatever the user
   enters and run it through the existing Anthropic API to split into 0..N subtasks,
   *before* the existing discovery flow. Seam: `NewTaskSheet.createTask()` ->
   new `PlannerAIService.generateSubtasksFromInput(_:)` -> new `SubTaskSplit` tool
   schema in `ClaudeAPIClient`. TDD: NetworkStub-driven tests first.
   - Open question to resolve when we start: does this production feature go on its
     own branch off `main` (so it ships independently of research), or ride this
     research branch? Likely its own branch.
2. **Research infra:** build this folder's loop, prove it end-to-end.
3. **Optimize the FM** to match the Sonnet behavior from step 1.

---

## Architecture: split inheritance

We do NOT adopt either prior harness wholesale. We take the best layer from each.

| Layer | Inherited from | Why |
|---|---|---|
| Control loop (propose -> run -> keep/reset on one number) | juna + Karpathy `autoresearch` | simple; the experiment collapses to one headline score |
| Reporting (HTML / SSE dashboard, lineage) | juna `llm-heuristic-scientists-workshop` | better UI |
| `definition.py` / `scenarios.py` split | juna | immutable contract vs. real-world examples |
| **Experiment config registry** | **tada FMDiscovery (`Configs.swift`)** | multi-node topologies, per-node temps, multiple training strategies — the complexity FMDiscovery proved we need |
| Training tracks (SFT / ORPO + hyperparams) | FMDiscovery | the preference/SFT space |

Key principle: **complexity lives in the experiment *definition*, not the control
loop.** No matter how many nodes/temps an experiment has, it still produces one F1
number, so the keep-commit-or-reset loop stays simple.

Language: Python + `uv` (so it talks to RunPod and LLM providers easily).

---

## Roles

| Role | Model | Notes |
|---|---|---|
| Scientist (proposes next experiment, edits `experiments.py`) | **Sonnet 4.6** | |
| Gold (reference task extractions, frozen once) | **Sonnet 4.6** | same call as the app feature |
| Judge (adjudicates fuzzy matches + quality) | **Sonnet 4.6** | only on the ambiguous residue |
| Candidate (the thing we optimize) | **Apple FM** (stock, then + adapter) | this is what ships in tada |
| Trainer (LoRA SFT / ORPO) | **RunPod** (L40S) | autonomous; closes the seam that made FMDiscovery pause for a human |

Local gpt-oss-20B is deliberately *not* used for now — using Sonnet everywhere except
candidate/trainer means the app migrates toward FM with Sonnet as the standing bar.

RunPod feasibility for Apple adapters is confirmed by Barrasso
(barrasso.me/posts/2026-04-09 — L40S, CUDA, Flash Attention, ~$0.89/hr, ~10k samples
several epochs in under an hour vs. ~18h on a MacBook Air).

---

## Files (the spine)

```
fm-ramble-to-tasks/
  CONTEXT.md          this file
  definition.py       IMMUTABLE — task contract, output schema, metric, judge
                      protocol, gold-gen prompt, frozen-gate rule. Scientist may NOT edit.
  scenarios.py        real-world inputs -> expected task sets, tagged by kind,
                      split train / val / frozen-test.
  experiments.py      MUTABLE registry the scientist edits (the Configs.swift analog).
  candidate.py        runs the Apple FM (stock or + adapter) for a given topology.
  eval.py             zero-task check + set-match P/R/F1 + judge-on-residue.
  loop.py             autonomous driver (propose -> run -> score -> git keep/reset).
  train_runpod.py     training track: package data -> launch L40S -> poll -> pull
                      .fmadapter -> register as candidate -> teardown. HARD $ cap + kill switch.
  dashboard/          juna's SSE dashboard.
  results.tsv / runs/ experiment log + per-run verdicts (untracked).
```

### `definition.py` (immutable contract)
- `Task(title)`, `Prediction = list[Task]` (0..N; `[]` valid).
- `MATCH_THRESHOLD` (embedding cosine to propose a pred<->gold match).
- `score(pred, gold, judge) -> Score`: zero-task is binary; otherwise bipartite-match
  pred<->gold (embedding >= threshold, judge breaks ties) -> precision / recall / F1.
- `JUDGE_RUBRIC`: (a) match adjudication, (b) per-task quality (atomic? actionable?
  faithful / no hallucination?).
- `GOLD_PROMPT`: frozen Sonnet prompt so gold is reproducible (same as app feature).
- `TEST_SPLIT_IS_FROZEN = True`.

### `scenarios.py` (data)
Tagged by kind — the kinds are what make the eval honest:
- `zero` — non-actionable rambling -> `[]` (the easiest case to get wrong).
- `single` — one intention.
- `multi` — distinct threads.
- `interleaved` — jumps back to an earlier thread; must NOT become duplicate tasks.
- false-positive bait — sounds task-ish, isn't actionable -> `[]`.
Split into train / val / frozen-test.

### `experiments.py` (mutable registry — what the scientist edits)
```python
class Topology(Enum):
    SINGLE_SHOT        # one call: extract 0..N tasks
    SEGMENT_EXTRACT    # segment ramble -> chunks; extract per chunk; dedup
    OVERGEN_FILTER     # generate many candidates hot, then filter/dedup cold
    BRAINSTORM_SELECT  # brainstorm intentions, keep only atomic+actionable
    EXTRACT_CRITIQUE   # extract, then self-critique node (hallucination? atomic?)

@dataclass
class TrainingSpec:        # None => inference-only experiment
    method: str           # "sft" | "orpo"
    data_recipe: str      # which gen recipe -> jsonl (the data lever)
    epochs: int
    lr: float
    lambda_or: float | None = None
    gpu: str = "L40S"

@dataclass
class Experiment:
    label: str
    topology: Topology
    temps: dict[str, float]    # PER-NODE temps, e.g. {"segment": 0.7, "extract": 0.2}
    candidate: str             # "fm-stock" | "adapter:rambl_v3a"
    training: TrainingSpec | None = None
```
This single shape captures everything that got complex in FMDiscovery: multiple nodes
(topology), per-node temps, multiple SFT/preference strategies, and the data recipe as
a first-class lever (where most of the gains hid last time).

---

## Eval — push toward "one trustworthy number"

The judge is the tax on autonomy (slow, costs money, noisy). Make as much of the score
deterministic as possible; reserve the judge for the residue.
1. Zero-task check — deterministic binary.
2. Set match — extracted vs. gold via embedding similarity + threshold -> P/R/F1.
3. Judge only the borderline matches and per-task quality.
Headline score = one F1-ish number (what keep/reset keys on); judge component logged
separately.

Frozen held-out gate is load-bearing here (small, fuzzy dataset = highly gameable),
unlike Karpathy's `val_bpb` which is ungameable and needs no gate.

---

## Control loop

```
1. Scientist (Sonnet) reads definition.py + recent results -> proposes ONE change to
   experiments.py (an inference tweak OR "request a new adapter").
2. Inference tweak: run candidate (Apple FM) over scenarios -> eval.py -> score.
3. Training request: train_runpod.py spins up L40S, trains, pulls .fmadapter,
   registers it as a new candidate -> then eval as above.
4. Score improved on the frozen gate? -> git commit (advance). Else -> git reset.
5. Append to results.tsv, update dashboard. Plateau -> pivot. Repeat.
```
The training track (step 3) no longer pauses for a human — that is the difference from
FMDiscovery.

---

## Status

- [x] Branch `research/fm-ramble-to-tasks` created off `main`.
- [x] Project folder + this plan of record.
- [ ] App feature (Sonnet ramble-split) in the tada app — NEXT.
- [ ] Research infra: definition.py / scenarios.py / experiments.py / eval.py / loop.py.
- [ ] RunPod training track.
- [ ] juna dashboard ported.
