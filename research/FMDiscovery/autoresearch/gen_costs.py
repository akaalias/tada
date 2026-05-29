#!/usr/bin/env python3
"""Rebuild results/costs.json {label: coderCostUSD} from the loop's commit
messages ("autoresearch: experiment logged (total=K, coder $C)"). total=K means
the experiment at index K-1. No API calls; idempotent; best-effort."""
import json, re, subprocess, pathlib

PKG = pathlib.Path(__file__).resolve().parent.parent
runs = PKG / "results" / "runs.jsonl"

idx2label = {}
if runs.exists():
    for l in runs.read_text(encoding="utf-8").splitlines():
        try:
            r = json.loads(l); idx2label[r["index"]] = r["label"]
        except Exception:
            pass

costs = {}
try:
    out = subprocess.run(["git", "log", "--all", "--pretty=%s"], cwd=str(PKG),
                         capture_output=True, text=True).stdout
except Exception:
    out = ""
for line in out.splitlines():            # newest first; first cost seen per label wins
    m = re.search(r"total=(\d+),\s*coder\s*\$([0-9.]+)", line)
    if m:
        label = idx2label.get(int(m.group(1)) - 1)
        if label and label not in costs:
            costs[label] = round(float(m.group(2)), 4)

(PKG / "results" / "costs.json").write_text(json.dumps(costs, indent=2), encoding="utf-8")
print(f"[gen_costs] wrote {len(costs)} costs")
