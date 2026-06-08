# fm-ramble-to-tasks

Autoresearch project: find an on-device Apple Foundation Model configuration (stock
or `.fmadapter`) that turns a free-form user input into 0..N atomic, actionable tasks
as well as Sonnet 4.6 does.

This is the step *before* discovery. FMDiscovery turns one clean one-liner into 7
questions. This project turns a messy, stream-of-consciousness input (already
transcribed to text by something like Wisp Flow — we never touch audio) into the
0..N one-liners that feed discovery.

Branch: `research/fm-ramble-to-tasks`. The production Sonnet feature that this
research aims to replace on-device already shipped on `feat/ramble-split`
(`PlannerAIService.splitIntoTasks`).

---

## The task

Input: free-form text. Zero, one, or many distinct intentions, possibly interleaved
or buried in non-actionable rambling.

Output: `0..N` atomic, actionable task one-liners. `[]` is a valid, correct answer.

Fixed policy (defines the task, not tunable): a single intention mentioned twice =>
ONE task; vague musing is NOT a task; every task must trace to the input (no
inventions); empty of tasks => `[]`.

---

## Architecture: fork FMDiscovery, add autonomous RunPod training

Decision (superseded the earlier juna-based plan): do NOT rebuild in juna's Python.
**Fork the FMDiscovery harness** — it already has the experiment-config registry, the
Sonnet judge + gold + frozen gate, the `run.sh` loop driving `claude` as the coder,
lineage/reporting, AND the Apple adapter training scripts. The only gap was that
training paused for a human (`REQUEST.md`). We close exactly that gap with a
self-directed RunPod training track.

Re-task the task-specific layer (schema, gold, judge rubric, metric, topologies,
prompts); keep the machinery (loop, runner, recording, training scripts); add RunPod.

### Where things run
- **RunPod (CUDA, e.g. L40S):** the trainer ONLY — Apple adapter toolkit `train` +
  `export_fmadapter` -> `.fmadapter`. The toolkit is Linux/CUDA-portable
  (`get_device()` picks cuda; deps are cross-platform); the base weights ship inside
  the toolkit's `assets/`, so no Apple re-download on the Pod. Strip the
  `require_ac_power.sh` (pmset) guard and the local pyenv/venv assumptions.
- **Your Mac:** everything else — the loop, the `claude` coder, the Sonnet judge, and
  **evaluating** the adapter (the Apple FM runtime that loads `.fmadapter` is
  macOS-26/Apple-Silicon only). The trained adapter comes back to the Mac to be scored.

So RunPod is only the trainer. Licensing (uploading Apple base weights to third-party
cloud): accepted, not a blocker. Don't ship the 12GB toolkit per run — bake it into a
RunPod **network volume** once and attach to ephemeral Pods; data (JSONL) and adapter
(~133MB) move per-run.

### Roles
| Role | Model | Notes |
|---|---|---|
| Scientist (proposes next experiment, edits Configs) | Sonnet 4.6 | via `claude` CLI, like FMDiscovery |
| Gold (reference task extractions, frozen) | Sonnet 4.6 | same behavior as the shipped app feature |
| Judge (adjudicates fuzzy matches + quality) | Sonnet 4.6 | only on the ambiguous residue |
| Candidate (the thing we optimize) | Apple FM (stock, then + adapter) | ships in tada |
| Trainer (LoRA SFT/ORPO) | RunPod (L40S) | autonomous; replaces the human pause |

---

## Eval — push toward "one trustworthy number"

The judge is the tax on autonomy (slow, costs money, noisy). Make as much of the
score deterministic as possible; reserve the judge for the residue.
1. Zero-task check — deterministic binary.
2. Set match — extracted vs. gold via embedding similarity + threshold -> P/R/F1.
3. Judge only the borderline matches and per-task quality (atomic? actionable? faithful?).
Headline score = one F1-ish number (what keep/reset keys on); judge component logged
separately. Frozen held-out gate is load-bearing (small, fuzzy dataset = gameable).

---

## Data

| Source | Volume | Role | Labels |
|---|---|---|---|
| Sonnet generator | thousands | training + synthetic eval | Sonnet |
| Real dogfooding | dozens | frozen held-out test | human-verified |

Synthetic = volume (incl. the SFT/ORPO training set). Real = anti-self-delusion gate
(synthetic rambles look like Sonnet's idea of a ramble, not real dictation). First real
held-out entry: the Franziska ramble (review 2024 tax doc / talk about August / take
out trash -> 3 tasks).

---

## Package layout (Swift, forked from FMDiscovery)

```
fm-ramble-to-tasks/
  Package.swift          RambleSplit package, macOS 26
  Sources/Contract/      RambleResult (the 0..N task one-liners). IMMUTABLE spec.
  Sources/SplitAgent/    candidate inference (on-device Apple FM).
      SplitConfig.swift  the lever space (topology, temp/sampling, adapter path)
      ConfiguredAgent    topology dispatch + FoundationModels calls
      Generated.swift    @Generable FMRambleSplit (guided generation)
      Prompts.swift      system instructions (mirrors the app's split contract)
      Configs.swift      experiment registry (the mutable lever space)
  Sources/fmramble/      CLI: availability | inspect (evaluate next)
  [todo] Sources/EvalBench/  RambleInputs (input set, synthetic + real held-out) +
                             GoldCase + GoldGenerator (Sonnet gold) + Sonnet judge +
                             set-match P/R metric + runner + gate. All Swift — mirrors
                             FMDiscovery. NO Python, NO scenarios.py (that was the
                             dropped juna plan).
  [todo] gold/               frozen Sonnet-generated gold cases (GoldStore JSON)
  [todo] autoresearch/       run.sh loop + RunPod training driver
```

Standalone SwiftPM: build/run with `swift build` / `swift run fmramble ...` (NOT
xcodebuild — that's only for the Tada app).

---

## Status

- [x] App feature (Sonnet split) shipped on `feat/ramble-split`; behavior is the gold target.
- [x] Architecture decided: fork FMDiscovery + autonomous RunPod training (juna dropped).
- [x] RunPod feasibility confirmed: Apple toolkit is CUDA-portable; base weights ship in
      the toolkit; only training goes to RunPod, eval stays on Mac.
- [x] **Phase 1 scaffold:** RambleSplit package builds; FM AVAILABLE; stock on-device FM
      splits the Franziska ramble into the 3 correct tasks (baseline candidate works).
- [ ] EvalBench: gold loader, Sonnet judge, deterministic set-match P/R metric, runner, CLI `evaluate`.
- [ ] GoldGenerator (Sonnet) for synthetic gold + RambleInputs incl. real held-out (Franziska +).
- [ ] More topologies in Configs (segmentExtract, overGenerateFilter, ...).
- [ ] autoresearch loop (run.sh driving claude) re-tasked.
- [ ] RunPod training driver (the autonomy seam) + network volume + cost guards.
