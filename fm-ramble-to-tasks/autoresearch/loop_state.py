#!/usr/bin/env python3
"""Compute the loop's lineage/patience state for run.sh and print shell KEY=VALUE
lines for `eval`. Two parents per program: the reigning elite (best-fitness dev
run) and the inspiration program (most recent dev run). PATIENCE: if that many dev
programs in a row have not produced a new best (and no pivot since), the next one
is a PIVOT — drop the elite, continue only from the inspiration program.

The patience counter resets on a KEEP (new best) OR a PIVOT, so a fresh direction
gets a full PATIENCE window before pivoting again.

Usage: loop_state.py [PATIENCE]
"""
import json, sys, pathlib

PKG = pathlib.Path(__file__).resolve().parent.parent
RUNS = PKG / "results" / "programs.jsonl"
META = PKG / "results" / "lineage_meta.json"
patience = int(sys.argv[1]) if len(sys.argv) > 1 else 5


def main():
    rows = [json.loads(l) for l in RUNS.read_text().splitlines() if l.strip()] if RUNS.exists() else []
    dev = sorted([r for r in rows if r.get("subset") != "test"], key=lambda r: r.get("index", 0))
    meta = json.loads(META.read_text()) if META.exists() else {}

    def emit(k, v): print(f"{k}={v}")

    if not dev:
        for k, v in [("ELITE", ""), ("ELITE_FIT", "0"), ("INSPIRATION", ""), ("PATIENCE_CNT", "0"), ("PIVOT", "0")]:
            emit(k, v)
        return

    champ = max(dev, key=lambda r: r.get("fitness", 0.0))
    prev = dev[-1]
    last_reset = -1
    for i, r in enumerate(dev):
        if r.get("kept") or meta.get(r["label"], {}).get("pivot"):
            last_reset = i
    cnt = max(0, (len(dev) - 1) - last_reset)

    emit("ELITE", champ["label"])
    emit("ELITE_FIT", f"{champ.get('fitness', 0.0):.3f}")
    emit("INSPIRATION", prev["label"])
    emit("PATIENCE_CNT", cnt)
    emit("PIVOT", 1 if cnt >= patience else 0)


if __name__ == "__main__":
    main()
