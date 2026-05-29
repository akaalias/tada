# Adapter track (lever 7) — setup & runbook

Goal: fine-tune a LoRA adapter for the on-device model so per-call discovery
*judgment* improves (the coverage gap prompting/RAG can't close). Trained on the
`corpus/` demonstration bank (disjoint from the frozen eval `gold/` — no leak).

## Sequence (who does what)

1. **YOU — download the toolkit** (Apple ID gated; I can't):
   https://developer.apple.com/download/foundation-models-adapter/
   Get the **v26.0.0** toolkit (matches macOS 26). Unzip somewhere, e.g.
   `~/adapter_training_toolkit_v26`. (No entitlement needed to train/test locally.)
2. **ME — scale the corpus** to ~300 pairs (`gen_corpus.py`, running/scalable).
3. **EITHER — train** (a few hours on the M4 Max):
   `TOOLKIT=~/adapter_training_toolkit_v26 ./research/FMDiscovery/autoresearch/train_adapter.sh`
   Produces `research/FMDiscovery/adapter/exports/discovery_v1.fmadapter` (~160 MB).
4. **ME — integrate** the adapter knob into the Swift agent (small edits below).
   This touches `Sources/DiscoveryAgent`, which the loop also edits — so it must
   be done while the loop is STOPPED. That is the restart point: you stop the
   loop, I apply + commit the edits, you restart `run.sh`.
5. The loop can then run adapter-backed experiments; they appear in the dashboard
   with a gold **LoRA** badge.

## Training data
`format_training_data.py` turns `corpus/*.json` into `adapter/data/{train,valid}.jsonl`
(Apple's chat schema: `[{"role":"user","content":INSTR+task},{"role":"assistant","content":<plan JSON>}]`),
90/10 split. Trains only on corpus (never the eval set).

## Caveats
- **OS-version pinned:** an adapter is tied to ONE system-model version; a macOS
  model update requires retraining with the matching toolkit version.
- **Physical device only** for testing (not Simulator) — fine, we run on this Mac.
- Toolkit wants **Python 3.11** (host default is 3.12; `train_adapter.sh` makes a 3.11 venv via pyenv).

## Swift integration to apply at the restart point (step 4)

`Sources/DiscoveryAgent/DiscoveryConfig.swift` — add a knob:
```swift
public var adapter: String?   // absolute path to a .fmadapter, or nil for the stock base model
```
(add `adapter: String? = nil` to `init`, store it.)

`Sources/DiscoveryAgent/ConfiguredAgent.swift` — resolve the model once and pass it to every session:
```swift
import FoundationModels
private func model() throws -> SystemLanguageModel {
    if let path = config.adapter {
        let a = try SystemLanguageModel.Adapter(fileURL: URL(filePath: path))
        return SystemLanguageModel(adapter: a)
    }
    return SystemLanguageModel.default
}
```
Then change each `LanguageModelSession { Prompts.x }` to
`LanguageModelSession(model: try model()) { Prompts.x }`.

`Sources/DiscoveryAgent/Configs.swift` — add an adapter config, e.g.:
```swift
"exp_adapter": DiscoveryConfig(topology: .ragFewShot,
    adapter: "/Users/alexisrondeau/Workshop/tada/research/FMDiscovery/adapter/exports/discovery_v1.fmadapter"),
```
