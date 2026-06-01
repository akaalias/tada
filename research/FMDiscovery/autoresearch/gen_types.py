#!/usr/bin/env python3
"""Derive each experiment's METHOD TYPE and write results/types.json — a side-car
keyed by label, exactly like operators.json / costs.json (never edits the immutable
runs.jsonl).

Taxonomy (the two lever groups from the onboarding):
  Inference-Time          — in-context / decoding / RAG / topology only; no weight change.
  Supervised Fine-Tuning  — runs on a LoRA adapter trained by IMITATION on Sonnet gold.
  Preference (ORPO)       — runs on a LoRA adapter trained on chosen/rejected PREFERENCE pairs.

Rule: a config is weight-level iff its DiscoveryConfig sets `adapter:`. The training
method is read from the adapter filename (…orpo… -> ORPO; else SFT). No adapter -> Inference-Time.
"""
import json, re, pathlib

PKG = pathlib.Path(__file__).resolve().parent.parent
CONFIGS = PKG / "Sources" / "DiscoveryAgent" / "Configs.swift"
RUNS = PKG / "results" / "runs.jsonl"
OUT = PKG / "results" / "types.json"

INFER = "Inference-Time"
SFT = "Supervised Fine-Tuning"
ORPO = "Preference (ORPO)"
GRPO = "Reinforcement (GRPO)"


def classify_adapter(path):
    p = path.lower()
    if "grpo" in p:
        return GRPO
    return ORPO if "orpo" in p else SFT


def parse_configs(text):
    """label -> type, by scanning each `"label": DiscoveryConfig(...)` entry until
    the next entry. An entry is weight-level iff it contains an `adapter:` path."""
    out, label, buf = {}, None, []
    label_re = re.compile(r'^\s*"([A-Za-z0-9_]+)"\s*:\s*DiscoveryConfig\(')

    def flush():
        if label is None:
            return
        m = re.search(r'adapter:\s*"([^"]+)"', " ".join(buf))
        out[label] = classify_adapter(m.group(1)) if m else INFER

    for line in text.splitlines():
        m = label_re.match(line)
        if m:
            flush()
            label, buf = m.group(1), [line]
        elif label is not None:
            buf.append(line)
    flush()
    return out


def main():
    types = parse_configs(CONFIGS.read_text()) if CONFIGS.exists() else {}
    # Fallback for any logged label missing from Configs.swift (e.g. a since-removed
    # config) so the table is never blank — infer from the name.
    if RUNS.exists():
        for ln in RUNS.read_text().splitlines():
            ln = ln.strip()
            if not ln:
                continue
            lab = json.loads(ln)["label"]
            if lab in types:
                continue
            low = lab.lower()
            types[lab] = (GRPO if "grpo" in low else ORPO if "orpo" in low
                          else SFT if low.startswith("adapter") else INFER)

    payload = {"_meta": "label -> method type. Derived from Configs.swift (does the "
                        "config set adapter:?) — never hand-edited. Inference-Time = no "
                        "weight change; Supervised Fine-Tuning = adapter trained by "
                        "imitation; Preference (ORPO) = preference pairs; "
                        "Reinforcement (GRPO) = adapter trained by RL on a judge reward."}
    payload.update(dict(sorted(types.items())))
    OUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"[gen_types] wrote {OUT.relative_to(PKG)} ({len(types)} labels)")


if __name__ == "__main__":
    main()
