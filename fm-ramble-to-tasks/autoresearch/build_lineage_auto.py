#!/usr/bin/env python3
"""Program lineage — TWO-PARENT model.

Each program's parents are the reigning elite (best-fitness dev run when it ran)
and the inspiration program, as recorded by the loop in results/lineage_meta.json.
A PIVOT drops the elite and keeps only the inspiration parent. Falls back to the cheap
elite-at-runtime heuristic for any label without recorded lineage (e.g. pre-feature runs).

Writes both files the lineage view reads:
  results/lineage_auto.json  — node facts (+ edges, + pivot flag)
  results/lineage_prose.json — the edges in the format the view consumes
"""
import json, re, pathlib

RES = pathlib.Path(__file__).resolve().parent.parent / "results"


def kind(label):
    if re.fullmatch(r"adapter_gad.*", label): return "gad"
    if re.fullmatch(r"adapter_grpo.*", label): return "grpo"
    if re.fullmatch(r"adapter_orpo.*", label): return "orpo"
    if label.startswith("adapter"): return "sft"
    return "inference"   # baseline + progNNN: prompting / retrieval / decoding / pipeline


def main():
    runs = RES / "programs.jsonl"
    if not runs.exists():
        print("no programs.jsonl; nothing to do"); return
    rows = [json.loads(l) for l in runs.read_text().splitlines() if l.strip()]
    dev = sorted([r for r in rows if r.get("subset") != "test"], key=lambda r: r.get("index", 0))
    meta = json.loads((RES / "lineage_meta.json").read_text()) if (RES / "lineage_meta.json").exists() else {}

    nodes, edges, champ = {}, [], None   # champ = (label, fitness) for the fallback
    for r in dev:
        label, q, kept = r["label"], r.get("fitness", 0.0), bool(r.get("kept"))
        info = meta.get(label, {})
        pivot = bool(info.get("pivot"))
        n = nodes.get(label)
        if n is None:
            nodes[label] = {"label": label, "index": r.get("index", 0),
                            "fitness": q, "kept": kept, "kind": kind(label), "pivot": pivot}
        else:
            n["fitness"] = max(n["fitness"], q); n["kept"] = n["kept"] or kept; n["pivot"] = n["pivot"] or pivot
        parents = info.get("parents")
        if parents:
            # recorded lineage: parents[0]=elite (parent), the rest=inspiration (inspiration);
            # a pivot has only the inspiration parent, drawn as inspiration.
            for j, p in enumerate(parents):
                rel = "inspiration" if (pivot or j > 0) else "parent"
                edges.append({"from": p, "to": label, "relation": rel})
        elif champ and champ[0] != label:
            edges.append({"from": champ[0], "to": label, "relation": "parent"})   # fallback
        if kept and (champ is None or q > champ[1]):
            champ = (label, q)

    nodelist = sorted(nodes.values(), key=lambda n: n["index"])
    valid = {n["label"] for n in nodelist}
    edges = [e for e in edges if e["from"] in valid and e["to"] in valid]
    auto = {"_meta": "Two-parent lineage (elite + inspiration; pivots drop the elite) from "
                     "results/lineage_meta.json; elite-at-runtime fallback otherwise.",
            "method": "two-parent", "nodes": nodelist, "edges": edges}
    (RES / "lineage_auto.json").write_text(json.dumps(auto, indent=2))
    prose = {"_meta": "Edges in the prose-edge format the lineage view consumes.", "edges": edges}
    (RES / "lineage_prose.json").write_text(json.dumps(prose, indent=2))
    npivot = sum(1 for n in nodelist if n.get("pivot"))
    print(f"wrote lineage: {len(nodelist)} nodes, {len(edges)} edges, {npivot} pivots")


if __name__ == "__main__":
    main()
