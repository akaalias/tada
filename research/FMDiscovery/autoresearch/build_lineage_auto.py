#!/usr/bin/env python3
"""Cheap, automatic experiment lineage — the "champion-at-runtime" heuristic.

No prose, no hand-mining: each run's parent is simply the reigning champion when it
ran — the highest-quality KEPT run with a smaller index. This is what you can derive
for free from runs.jsonl (index / kept / quality), and the linear champion spine falls
out as the kept->kept backbone. It is deliberately naive: it attaches everything to the
score leader, so it cannot see that (e.g.) the RL adapters warm-started the v2a SFT
adapter rather than the higher-scoring inference champion. That gap is the point — we
compare this against the hand-mined lineage_prose.json.

    python build_lineage_auto.py   ->   ../results/lineage_auto.json
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
    rows = [json.loads(l) for l in (RES / "runs.jsonl").read_text().splitlines() if l.strip()]
    rows.sort(key=lambda r: r.get("index", 0))

    nodes, edges, seen = {}, [], set()
    champ = None                      # (label, quality) of the best kept run so far
    for r in rows:
        label, q, kept = r["label"], r.get("quality", 0.0), bool(r.get("kept"))
        # node (dedupe by label: keep min index, max quality, kept if ever kept)
        n = nodes.get(label)
        if n is None:
            nodes[label] = {"label": label, "index": r.get("index", 0),
                            "quality": q, "kept": kept, "kind": kind(label)}
        else:
            n["quality"] = max(n["quality"], q); n["kept"] = n["kept"] or kept
        # parent = reigning champion at this run's first appearance
        if label not in seen:
            seen.add(label)
            if champ and champ[0] != label:
                edges.append({"from": champ[0], "to": label, "relation": "reigning-champion"})
        # update champion AFTER assigning the parent
        if kept and (champ is None or q > champ[1]):
            champ = (label, q)

    out = {
        "_meta": "Automatic lineage (champion-at-runtime): parent = highest-quality KEPT "
                 "run with a smaller index. Derived purely from runs.jsonl; no prose. "
                 "Naive by design — compare against lineage_prose.json.",
        "method": "champion-at-runtime",
        "nodes": sorted(nodes.values(), key=lambda n: n["index"]),
        "edges": edges,
    }
    (RES / "lineage_auto.json").write_text(json.dumps(out, indent=2))
    print(f"wrote {RES/'lineage_auto.json'}: {len(out['nodes'])} nodes, {len(edges)} edges")
    champs = [n["label"] for n in out["nodes"] if n["kept"]]
    print("champion spine (kept runs):", " -> ".join(champs))


if __name__ == "__main__":
    main()
