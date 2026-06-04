#!/usr/bin/env python3
"""Append parent->child lineage edges for one or more experiments to
results/lineage_prose.json, idempotently — so the lineage.html page updates
automatically after each experiment (this is the one step record_experiment.sh
used to leave manual).

Mirrors the hand-mined convention exactly:
  - uses-adapter : from the experiment's pipeline-spec generate-stage knobs.model
                   (the on-device LoRA the call runs) -> the experiment
  - builds-on    : from the topology ANCESTOR (lowest-index OTHER config with the
                   same DiscoveryConfig topology) -> the experiment

SURGICAL: only appends edge objects before the closing ] of the edges array;
it never reformats the rest of the curated file. Endpoints are validated against
results/lineage_auto.json (what the renderer actually positions nodes from), so an
edge is only added if both ends are real graph nodes.

Usage: add_lineage_edges.py <label> [<label> ...]
"""
import sys, re, json, pathlib

PKG   = pathlib.Path(__file__).resolve().parent
PROSE = PKG / "results" / "lineage_prose.json"
AUTO  = PKG / "results" / "lineage_auto.json"
CFG   = (PKG / "Sources" / "DiscoveryAgent" / "Configs.swift").read_text()

# topology -> [configs in source order]; and label -> topology
TOPO = {}
for m in re.finditer(r'"(exp\d+)":\s*DiscoveryConfig\(topology:\s*\.(\w+)', CFG):
    TOPO.setdefault(m.group(2), []).append(m.group(1))
LABEL_TOPO = {e: t for t, es in TOPO.items() for e in es}


def adapter_node(label):
    p = PKG / "results" / "pipelines" / f"{label}.json"
    if not p.exists():
        return None
    for s in json.loads(p.read_text()).get("stages", []):
        m = s.get("knobs", {}).get("model")
        if m and m.startswith("adapter_"):
            return m
    return None


def ancestor(label):
    t = LABEL_TOPO.get(label)
    if not t:
        return None
    peers = sorted((e for e in TOPO[t] if e != label), key=lambda x: int(x[3:]))
    return peers[0] if peers else None


def edges_for(label):
    out, a = [], adapter_node(label)
    if a:
        out.append({"from": a, "to": label, "relation": "uses-adapter",
                    "evidence": f"knobs.model = {a}", "confidence": "high"})
    anc = ancestor(label)
    if anc:
        out.append({"from": anc, "to": label, "relation": "builds-on",
                    "evidence": f"same {LABEL_TOPO[label]} topology as {anc}, crossed onto {a or 'the adapter'}",
                    "confidence": "high"})
    return out


def main():
    labels = sys.argv[1:]
    if not labels:
        print("usage: add_lineage_edges.py <label> [...]"); sys.exit(1)

    doc   = json.loads(PROSE.read_text())
    nodes = {n["label"] for n in json.loads(AUTO.read_text())["nodes"]}
    have  = {(e["from"], e["to"], e["relation"]) for e in doc["edges"]}

    new = []
    for L in labels:
        for e in edges_for(L):
            key = (e["from"], e["to"], e["relation"])
            if key in have:
                continue
            if e["from"] not in nodes or e["to"] not in nodes:
                print(f"[edges] skip {e['from']}->{e['to']} ({e['relation']}): endpoint not a graph node yet")
                continue
            have.add(key); new.append(e)

    if not new:
        print("[edges] nothing new to add"); return

    text = PROSE.read_text()
    idx  = text.rstrip().rfind("]")            # close of the edges array (the last array)
    head = text[:idx].rstrip()                 # ends right after the last edge object
    block = ",\n".join("    " + json.dumps(e, ensure_ascii=False) for e in new)
    PROSE.write_text(head + ",\n" + block + "\n  ]\n}\n")
    print("[edges] added " + str(len(new)) + ": " + ", ".join(f"{e['from']}->{e['to']}" for e in new))


main()
