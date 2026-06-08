#!/usr/bin/env python3
"""Record one experiment's lineage: its two parents (champion + previous) and whether
it was a PIVOT (champion dropped, continued only from the previous experiment).
Written to results/lineage_meta.json, keyed by label; build_lineage_auto.py turns it
into the lineage view's edges.

Usage: record_lineage.py <label> <champion> <previous> <pivot 0|1>
"""
import json, sys, pathlib

PKG = pathlib.Path(__file__).resolve().parent.parent
META = PKG / "results" / "lineage_meta.json"


def main():
    label, champ, prev, pivot = sys.argv[1], sys.argv[2], sys.argv[3], (sys.argv[4] == "1")
    m = json.loads(META.read_text()) if META.exists() else {}
    parents = [prev] if pivot else [champ, prev]   # pivot drops the champion
    seen = []
    for p in parents:
        if p and p != label and p not in seen:
            seen.append(p)
    m[label] = {"parents": seen, "pivot": pivot}
    META.write_text(json.dumps(m, indent=2))
    print(f"[record_lineage] {label}: parents={seen} pivot={pivot}")


if __name__ == "__main__":
    main()
