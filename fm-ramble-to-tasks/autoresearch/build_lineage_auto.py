#!/usr/bin/env python3
"""Cheap, automatic experiment lineage — the "champion-at-runtime" heuristic.

No prose, no hand-mining: each run's parent is simply the reigning champion when it
ran — the highest-quality KEPT run with a smaller index. Derived for free from
runs.jsonl (index / kept / quality); the linear champion spine falls out as the
kept->kept backbone.

Writes BOTH files the lineage view reads:
  results/lineage_auto.json  — node facts (+ the auto edges)
  results/lineage_prose.json — the edges in the prose-edge format the view consumes

    python build_lineage_auto.py
"""
import json, re, pathlib

RES = pathlib.Path(__file__).resolve().parent.parent / "results"


def kind(label):
    if re.fullmatch(r"adapter_gad.*", label): return "gad"
    if re.fullmatch(r"adapter_grpo.*", label): return "grpo"
    if re.fullmatch(r"adapter_orpo.*", label): return "orpo"
    if label.startswith("adapter"): return "sft"
    return "inference"   # baseline + expNNN: prompting / retrieval / decoding / pipeline


def main():
    runs = RES / "runs.jsonl"
    if not runs.exists():
        print("no runs.jsonl; nothing to do"); return
    rows = [json.loads(l) for l in runs.read_text().splitlines() if l.strip()]
    rows.sort(key=lambda r: r.get("index", 0))

    nodes, edges, seen = {}, [], set()
    champ = None                      # (label, quality) of the best kept run so far
    for r in rows:
        label, q, kept = r["label"], r.get("quality", 0.0), bool(r.get("kept"))
        n = nodes.get(label)
        if n is None:
            nodes[label] = {"label": label, "index": r.get("index", 0),
                            "quality": q, "kept": kept, "kind": kind(label)}
        else:
            n["quality"] = max(n["quality"], q); n["kept"] = n["kept"] or kept
        if label not in seen:
            seen.add(label)
            if champ and champ[0] != label:
                edges.append({"from": champ[0], "to": label, "relation": "builds-on"})
        if kept and (champ is None or q > champ[1]):
            champ = (label, q)

    nodelist = sorted(nodes.values(), key=lambda n: n["index"])
    auto = {
        "_meta": "Automatic lineage (champion-at-runtime): parent = highest-quality KEPT "
                 "run with a smaller index. Derived purely from runs.jsonl; no prose.",
        "method": "champion-at-runtime", "nodes": nodelist, "edges": edges,
    }
    (RES / "lineage_auto.json").write_text(json.dumps(auto, indent=2))
    # The lineage view reads node facts from lineage_auto.json and EDGES from
    # lineage_prose.json — so emit the same auto edges there (relation builds-on).
    prose = {"_meta": "Auto edges (champion-at-runtime) in the prose-edge format the "
                      "lineage view consumes.", "edges": edges}
    (RES / "lineage_prose.json").write_text(json.dumps(prose, indent=2))
    print(f"wrote lineage_auto.json + lineage_prose.json: {len(nodelist)} nodes, {len(edges)} edges")
    champs = [n["label"] for n in nodelist if n["kept"]]
    print("champion spine (kept runs):", " -> ".join(champs))


if __name__ == "__main__":
    main()
