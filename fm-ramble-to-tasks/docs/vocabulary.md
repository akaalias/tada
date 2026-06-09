# Vocabulary for our autoresearch loop (2026 landscape)

Reference note: how the current (2025–26) AI-lab ecosystem names the thing we're
building — an LLM-driven loop that proposes configurations, evaluates them against a
judged objective, keeps the best, and iterates. Captured June 2026.

## TL;DR — what we are

> An **LLM-guided reflective evolutionary search**: across an **evolutionary run**, a
> **mutation operator** (the coder LLM) proposes each **program** by **reflecting** on
> judged execution **traces** and recombining two parents — the **elite** + an
> **inspiration** — scored by a **rubric evaluator** behind a hard **verifier**, into a
> **program database**, with **pivots** (restarts) on plateau.

This is the FunSearch → AlphaEvolve → **GEPA** lineage. We adopt that family's
vocabulary directly (program / mutation / elite / inspiration / fitness / archive),
and borrow only **"infeasible"** from Vizier for verifier failures. We deliberately do
NOT use "Study/Trial" — the campaign is an **evolutionary run** (closer to the EA
mental model). See "Adopted vocabulary" below for the locked glossary.

## The families and their terms

### 1. Black-box / HPO scaffolding — Optuna, Google Vizier
The *bookkeeping* layer. `Study` (the campaign) · `Trial` (one config) · `Measurement`
(a reported score) · `incumbent` (best so far) · trial states incl. `INFEASIBLE`
(constraint violated) · `ask-tell` interface · `budget`.
- Optuna = a Python **library**, define-by-run, default sampler TPE, pruners
  (Median/Hyperband), ask-tell, states RUNNING/COMPLETE/PRUNED/FAIL.
- Vizier (Google) = a **service**; canonical source of `Study` / `Trial` /
  `Measurement` / `INFEASIBLE`; default GP-Bandit Bayesian optimization.
- Caveat: both optimize a *fixed numeric/categorical* space with a mathematical
  sampler. Our "sampler" is an LLM writing code → we adopt the **vocabulary**, not
  the frameworks.

### 2. Evolutionary program search — FunSearch, AlphaEvolve, OpenEvolve/CodeEvolve
Core idea: **the LLM is the mutation operator** inside an evolutionary loop.
`program database` / `archive` · `evaluator` · `fitness` · `island`-based populations ·
`MAP-Elites` quality-diversity archive · `elite` / `elitism` · `parent selection` ·
`mutation` (1 parent) vs `crossover`/`recombination` ("inspiration-based crossover") ·
`generation` · `checkpoint` · explore/exploit. AlphaEvolve evolves whole codebases and
optimizes multiple objectives (broader than single-function FunSearch).

### 3. Reflective prompt evolution — GEPA (ICLR 2026 oral; July 2025) ← closest match
`reflective prompt evolution` · `genetic-Pareto` · `reflection` on execution `traces`
(inputs/outputs/**failures/feedback**) · `feedback function` · `candidate pool` ·
`Pareto frontier` of candidates · `rollout` + `rollout budget` · mutate a `module`.
Thesis: *"Reflective Prompt Evolution Can Outperform RL."* Our coder reading the
judge's per-case notes from `program.md` and proposing the next config **is** reflective
mutation. NOTE: GEPA is explicitly **prompt-only** (a no-weight alternative to RL).

### 4. Agent-design search — ADAS / Meta Agent Search
`meta agent` (a "programmer of agents" writing a `forward()` function) · `archive` of
discovered agents · code-as-search-space · evaluate-on-held-out-validation → archive →
inform next. Our coder = the meta agent; our registry+lineage = the archive.

### 5. Declarative pipeline optimization — DSPy
`program` / `module` / `signature` · `metric` · `optimizer`, where **"optimize" =
"compile"**. GEPA is now a DSPy optimizer. Our SplitAgent pipeline = a `program/module`;
`quality` = the `metric`.

### 6. RL / eval substrate — RLVR & rubric rewards
`rollout` · `trajectory` · `episode` · `reward` · `policy` · `advantage` · `verifier`
(programmatic hard check) vs `reward model` / rubric `evaluator` · `RLVR` (RL with
verifiable rewards) · `RLRR` / rubric rewards · **co-evolving rubric** (the rubric
evolves with the policy so it can't be gamed → anti-reward-hacking). Our **spec gate =
a verifier**; our **Sonnet rubric judge = the evaluator / reward model**.

### 7. The umbrella framing — Sakana
`AI Scientist` (idea → experiment → write-up) · `agentic tree search` (v2) ·
`recursive self-improvement (RSI)`. Ours is a focused optimizer in this family, not a
full AI-scientist.

## Mapping (our parts → adopted terms)

| our thing | adopt | family |
|---|---|---|
| `run.sh` campaign | **Study** | Vizier/Optuna |
| one config built + evaluated | **Trial** | Vizier/Optuna |
| the eval result/score | **Measurement** / **fitness** | Vizier / EA |
| `quality` | **objective** (the **metric**) | DSPy/HPO |
| champion | **incumbent** (keep "champion" as synonym) | HPO/EA |
| spec-gate fail | **infeasible** trial / **verifier** failure | Vizier/RLVR |
| coder error / timeout | **failed** / **stopped** trial | Optuna |
| the coder | **LLM mutation operator** / **meta-agent** | EA/ADAS |
| build on champion + previous | **recombination** (2-parent); 1-parent = **mutation** | EA |
| pivot | **restart** | EA |
| champion-as-parent | **elitism** | EA |
| registry + lineage | **archive** | EA/ADAS |
| reading judge notes to propose next | **reflection** on **traces** | GEPA |
| Sonnet rubric judge | **rubric evaluator** / reward model | RLVR |
| per-case model generation | **rollout** | GEPA/RL |
| `TARGET` | **trial / rollout budget** | all |

Bonus idea worth stealing — **GEPA's Pareto-frontier selection**: keep configs that are
best on *at least one* case (per-instance winners) as parents, not just the single
global champion. Diversifies parents, improves generalization.

## LoRA addendum — once we train adapters, GEPA alone is too narrow

GEPA is **prompt-only** by design (its whole pitch is "skip the weight updates"). The
moment we add LoRA adapters, our search space spans **two regimes**, and the better
single anchor becomes **AlphaEvolve** (broad-artifact evolution) plus the **RL
post-training** vocabulary:

- A **Trial** now has a **kind / regime**:
  - **inference-time** (prompt / topology / decoding / schema) — GEPA/AlphaEvolve-style.
  - **weight-update** (a trained LoRA **adapter**) — itself sub-typed by training method:
    **SFT** (imitation) · **preference** (DPO/**ORPO**) · **RLVR / GRPO** (rubric-reward RL:
    `policy`, `reward`, `rollout`, `trajectory`, `advantage`) · **distillation / GAD**.
    (This is exactly our dashboard **Type** column.)
- New artifacts/terms: **adapter** / **checkpoint** / **provenance** (we already have
  `adapter_provenance.json`); training **corpus**; **preference pairs**.
- The judged **rubric becomes a reward model** when an adapter optimizes toward it →
  watch **reward hacking**; the **co-evolving rubric (RLER)** idea is the standard guard.
- **Multi-fidelity** matters: inference Trials are cheap, training Trials are expensive
  (RunPod) → cost-aware search, and our dev(validation) vs held-out test split is the
  generalization check. (cf. successive halving / Hyperband.)
- There's an explicit research thread for exactly this mixed space: **joint prompt +
  weight / policy optimization** ("Fine-Tuning and Prompt Optimization: Two Great Steps
  that Work Better Together"; "P²O: Joint Policy and Prompt Optimization").

Revised one-liner once adapters are in scope:

> An **LLM-guided reflective evolutionary search over a mixed inference-and-weights
> space**: each **Trial** is either an inference-time mutation (GEPA/AlphaEvolve-style)
> or a trained **adapter** (SFT / preference / RLVR-GRPO / distillation), evaluated by a
> **rubric evaluator** behind a **verifier**, with the rubric doubling as the **reward
> model** for the weight-update trials.

## Adopted vocabulary (DECIDED — this is the locked glossary)

We went **pure FunSearch/AlphaEvolve/GEPA**, with `evolutionary run` for the campaign
(not "Study") and `infeasible` borrowed from Vizier for verifier failures.

| concept | **canonical term** |
|---|---|
| the campaign (one `run.sh` invocation) | **evolutionary run** |
| the unit: a config built + evaluated (a table row); label `progNNN` | **program** |
| one loop turn / one coder call | **sample** |
| the coder LLM | **mutation operator** |
| derive from 1 parent / from 2 | **mutation** / **crossover** |
| best-so-far | **elite** |
| the other parent fed in | **inspiration** |
| the store (results + registry + lineage) | **program database** |
| scoring stack | **evaluator** = **verifier** (hard, spec gate) + **rubric judge** (soft) |
| the score | **fitness** |
| program that fails the verifier | **infeasible** |
| sample that errors/times out / logs nothing | **failed sample** |
| patience-driven fresh start | **pivot** (EA: restart) |
| one model generation on one case | **rollout** |
| best-per-instance set (future) | **Pareto frontier** |

Applied at every layer: Swift (`fitness`, `infeasible`), scripts (`ELITE`/`INSPIRATION`,
`programs.jsonl`, `samples.log`), JSON keys (`fitness`), filenames (`programs.jsonl`),
docs, logs (`program.md`), and the dashboard (Run log / Program lineage / The problem).

Once LoRA lands, a **program** carries a **kind**: `inference` vs `weight-update`
(SFT / ORPO / GRPO / GAD) — already the dashboard Type column.

## Sources
- GEPA: Reflective Prompt Evolution Can Outperform RL — https://arxiv.org/abs/2507.19457
- AlphaEvolve (DeepMind) — https://storage.googleapis.com/deepmind-media/DeepMind.com/Blog/alphaevolve-a-gemini-powered-coding-agent-for-designing-advanced-algorithms/AlphaEvolve.pdf
- CodeEvolve — https://arxiv.org/abs/2510.14150 ; OpenEvolve — https://huggingface.co/blog/codelion/openevolve
- ADAS / Meta Agent Search — https://arxiv.org/abs/2408.08435
- DSPy — https://dspy.ai/ ; DSPy metrics — https://dspy.ai/learn/evaluation/metrics/
- Prime Intellect verifiers (RL envs + evals) — https://github.com/PrimeIntellect-ai/verifiers
- Rubric-based reward modeling — https://arxiv.org/html/2509.21500v3
- Sakana RSI Lab — https://sakana.ai/rsi-lab/ ; AI Scientist v2 — https://arxiv.org/abs/2504.08066
