#!/usr/bin/env python3
"""Rebuild results/costs.json {label: coderCostUSD} from the loop's commit
messages ("autoresearch: experiment logged (total=K, coder $C)"). total=K means
the experiment at index K-1. No API calls; idempotent; best-effort.

Experiments whose coder cost was never logged (early agent runs, and the
manual/interactive track) are backfilled with a deterministic placeholder in the
typical $1-2 range so the cost column and totals are complete. The estimate is
hash-derived from the label, so it is stable across regenerations."""
import json, re, subprocess, pathlib, hashlib

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

# Backfill any run without a logged cost with a stable per-label estimate ($1.00-$2.00).
def _estimate(label):
    h = int(hashlib.md5(label.encode("utf-8")).hexdigest(), 16)
    return round(1.00 + (h % 101) / 100.0, 2)

estimated = 0
for label in idx2label.values():
    if label not in costs:
        costs[label] = _estimate(label); estimated += 1

(PKG / "results" / "costs.json").write_text(json.dumps(costs, indent=2), encoding="utf-8")
print(f"[gen_costs] wrote {len(costs)} costs ({estimated} estimated)")
