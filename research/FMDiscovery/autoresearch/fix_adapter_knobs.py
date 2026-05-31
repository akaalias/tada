#!/usr/bin/env python3
"""Deterministically stamp the CORRECT adapter onto each pipeline spec's first
on-device model call, from the ground truth in Configs.swift (the `adapter:` path)
— NOT from whatever Sonnet guessed off the note.

Fixes two bugs in the generated diagrams:
  1. MISSING LoRA node — adapter-backed experiments whose note didn't name the
     adapter (e.g. exp056 "native draw") got no model knob, so no LoRA node rendered.
  2. WRONG provenance family — labels like "champion-adapter"/"adapter-v1" resolve to
     the v1 training chain, but these configs actually use the v2a adapter.

Only the FIRST model-call stage is set (to the config's primary adapter); later model
stages are left untouched so donor/secondary adapters (e.g. a v2b donor in a transplant
experiment) are preserved. No API calls. Idempotent.
"""
import json, re, pathlib

PKG = pathlib.Path(__file__).resolve().parent.parent
CFG = PKG / "Sources" / "DiscoveryAgent" / "Configs.swift"
SPECS = PKG / "results" / "pipelines"
FM_KINDS = {"generate", "expand", "critique", "ensemble"}   # on-device model calls (match util.js FMK)


def config_adapters():
    """label -> display adapter name (resolver-friendly), from each registry entry's adapter: path."""
    text = CFG.read_text()
    out = {}
    for m in re.finditer(r'"(\w+)":\s*DiscoveryConfig\((.*?)\)', text, re.DOTALL):
        label, body = m.group(1), m.group(2)
        a = re.search(r'adapter:\s*"([^"]+)"', body)
        if not a:
            continue
        stem = pathlib.Path(a.group(1)).stem            # discovery_v2a_e1
        # "discovery_*" -> "adapter_*" so the dashboard family resolver (looks for
        # v2a / v2b / "adapter") always classifies it correctly.
        out[label] = stem.replace("discovery", "adapter", 1)
    return out


def main():
    adapters = config_adapters()
    fixed = []
    for spec_path in sorted(SPECS.glob("*.json")):
        label = spec_path.stem
        name = adapters.get(label)
        if not name:
            continue                                    # non-adapter experiment; leave it
        spec = json.loads(spec_path.read_text())
        stages = spec.get("stages", [])
        model_stages = [s for s in stages if s.get("kind") in FM_KINDS]
        if not model_stages:
            continue
        first = model_stages[0]
        knobs = first.setdefault("knobs", {})
        if knobs.get("model") == name:
            continue                                    # already correct
        knobs["model"] = name
        spec_path.write_text(json.dumps(spec, indent=2))
        fixed.append(f"{label} -> {name}")
    print(f"fixed {len(fixed)} specs:")
    for f in fixed:
        print("  " + f)


if __name__ == "__main__":
    main()
