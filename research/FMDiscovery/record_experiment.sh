#!/usr/bin/env bash
# record_experiment.sh — run ONE FMDiscovery experiment the RIGHT way, end-to-end,
# and produce EVERY dashboard artifact. This is the MANUAL (human-operator) mirror
# of what autoresearch/run.sh does automatically after each agent iteration.
#
# WHY THIS EXISTS: doing these steps by hand is error-prone. The harness OWNS
# results/runs.jsonl and results/*.json — never hand-edit them. This script only
# ever (a) runs the eval (which writes them) and (b) runs the official generator
# scripts. Use it for every experiment so nothing (the move, the diagram, the
# hypothesis, the lineage node) is ever missing again.
#
# THE PROCESS (in order — gen_pipeline reads program.md + the runs.jsonl note):
#   1. eval  --subset full --label <LABEL> --note "<move>"   (harness writes runs.jsonl + results/<LABEL>.json)
#   2. prepend ONE line to the program.md experiment log      (the "move" + quality + verdict + insight)
#   3. gen_pipeline.py <LABEL>   -> results/pipelines/<LABEL>.json  (hypothesis / technique / result + stage DIAGRAM + LoRA training-"move" column)
#   4. gen_costs.py / gen_types.py                            (backfill costs.json / types.json)
#   5. operators.json[<LABEL>] = "human"                      (manual track tag; the agent track tags "agent")
#   6. build_lineage_auto.py     -> results/lineage_auto.json (puts the NODE on the lineage page)
#
# HARD RULES (same as autoresearch/AGENT.md):
#   - NEVER hand-edit results/runs.jsonl or results/*.json — the eval writes them.
#   - NEVER modify Sources/{EvalBench,Contract,fmresearch}, gold/, the judge, the metric, or the spec gate.
#   - Each experiment ADDS a new named DiscoveryConfig (keep all old configs); pick the next free expNNN.
#   - Gate on FULL-30 + GREEDY. A delta <=0.03 vs the prior best is noise.
#
# NOT AUTOMATED (do by hand): the lineage parent->child EDGES live in
#   results/lineage_prose.json and are HAND-MINED prose. After this script, add the
#   new node's edges there (e.g. exp060 <- adapter_grpo_kl_e1 "uses-adapter",
#   exp060 compares-to exp056), then re-open lineage.html.
#
# Usage:
#   record_experiment.sh <LABEL> --note "<move>" [--agent <AGENT=LABEL>] [--insight "<one-line>"] [--record-only]
#     --record-only : skip the eval (the run is ALREADY logged); just (re)build artifacts 2-6.

set -uo pipefail
REPO="/Users/alexisrondeau/Workshop/tada"
PKG="$REPO/research/FMDiscovery"
AR="$PKG/autoresearch"
RES="$PKG/results"

LABEL="${1:?usage: record_experiment.sh <LABEL> --note \"<move>\" [--agent A] [--insight T] [--record-only]}"; shift
AGENT="$LABEL"; NOTE=""; INSIGHT=""; RECORD_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent)       AGENT="$2"; shift 2;;
    --note)        NOTE="$2"; shift 2;;
    --insight)     INSIGHT="$2"; shift 2;;
    --record-only) RECORD_ONLY=1; shift;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

set -a; [ -f "$REPO/.env" ] && source "$REPO/.env"; set +a
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "[record] ERROR: ANTHROPIC_API_KEY not set (needed for the judge + gen_pipeline)"; exit 1
fi

# --- 1. eval (the harness judges + logs) ----------------------------------
if [ "$RECORD_ONLY" -eq 0 ]; then
  if grep -q "\"label\":\"$LABEL\"" "$RES/runs.jsonl" 2>/dev/null; then
    echo "[record] ERROR: label $LABEL already in runs.jsonl — duplicate labels corrupt the dashboard. Pick the next free expNNN."; exit 1
  fi
  [ -n "$NOTE" ] || { echo "[record] ERROR: --note \"<move>\" is required for a real run"; exit 1; }
  echo "[record] eval $LABEL (agent=$AGENT) on full-30 greedy ..."
  caffeinate -i swift run --package-path "$PKG" fmresearch evaluate \
    --agent "$AGENT" --subset full --label "$LABEL" --note "$NOTE" || { echo "[record] eval failed"; exit 1; }
fi

# --- PUBLISH-LAST: stash the eval's row OUT of runs.jsonl so the dashboard never
#     shows a half-finished row. We build the diagram/spec first, then re-append the
#     row + rebuild lineage together — so a row only ever appears once its diagram,
#     operator, type, and lineage node all exist. (gen_pipeline reads program.md, not
#     the row, so it works while the row is stashed.) In --record-only the row is
#     already public, so we just copy it out and skip the re-append.
STASH="$RES/.${LABEL}.row.stash"
if [ "$RECORD_ONLY" -eq 0 ]; then
  python3 - "$RES/runs.jsonl" "$LABEL" "$STASH" <<'PY' || { echo "[record] ERROR: could not stash $2 row"; exit 1; }
import json, sys
runs, label, stash = sys.argv[1], sys.argv[2], sys.argv[3]
lines = [l for l in open(runs).read().splitlines() if l.strip()]
if not lines or json.loads(lines[-1]).get("label") != label:
    sys.stderr.write(f"last runs.jsonl row is not {label} — refusing to stash\n"); sys.exit(1)
open(stash, "w").write(lines[-1] + "\n")                    # hold the row
open(runs, "w").write("\n".join(lines[:-1]) + "\n")          # remove it from the table
PY
  PUBLISH_LAST=1
else
  grep "\"label\":\"$LABEL\"" "$RES/runs.jsonl" | tail -1 > "$STASH" || { echo "[record] ERROR: no row for $LABEL"; exit 1; }
  PUBLISH_LAST=0
fi

# Authoritative facts come from the stashed row (NOT from the args).
IFS=$'\t' read -r Q KEPT NOTE < <(python3 - "$STASH" <<'PY'
import json, sys
r = json.loads(open(sys.argv[1]).read().strip())
print(f"{r['quality']:.3f}\t{'new best' if r.get('kept') else 'discarded'}\t{r.get('note','')}")
PY
) || { echo "[record] ERROR: could not read stashed row for $LABEL"; exit 1; }
echo "[record] $LABEL: quality=$Q ($KEPT)$([ "$PUBLISH_LAST" = 1 ] && echo ' (row stashed — will publish last)')"

# --- 2. prepend the program.md experiment-log line ------------------------
python3 - "$PKG/program.md" "$LABEL" "$NOTE" "$Q" "$KEPT" "$INSIGHT" <<'PY'
import sys
path, label, note, q, kept, insight = sys.argv[1:7]
line = f"- {label} {note} — quality {q} (full-30 greedy), {kept}" + (f", {insight}" if insight else "") + "\n"
t = open(path, encoding="utf-8").read()
anchor = "## The setup (Karpathy mapping)\n"
i = t.find(anchor)
if i < 0:                                  # fallback: append
    open(path, "a", encoding="utf-8").write("\n" + line)
else:
    j = i + len(anchor)
    while j < len(t) and t[j] == "\n":     # skip the blank line after the header
        j += 1
    open(path, "w", encoding="utf-8").write(t[:j] + line + t[j:])
print("[record] prepended program.md log line")
PY

# --- 3. pipeline spec: hypothesis/technique/result + DIAGRAM + LoRA move ---
python3 "$AR/gen_pipeline.py" "$LABEL" || echo "[record] WARN: gen_pipeline failed for $LABEL"

# --- PUBLISH: the spec now exists, so re-append the row. From here the table
#     row, its diagram, operator, type, and lineage node all land together. ---
if [ "${PUBLISH_LAST:-0}" -eq 1 ]; then
  cat "$STASH" >> "$RES/runs.jsonl"
  echo "[record] published $LABEL row (spec was ready first)"
fi
rm -f "$STASH"

# --- 4. costs + method-type backfill --------------------------------------
python3 "$AR/gen_costs.py" 2>/dev/null || true
python3 "$AR/gen_types.py"  2>/dev/null || true

# --- 5. operator tag = human (this is the manual track) -------------------
OPF="$RES/operators.json"; [ -f "$OPF" ] || echo '{}' > "$OPF"
if command -v jq >/dev/null 2>&1; then
  tmp=$(jq --arg l "$LABEL" '.[$l]="human"' "$OPF") && printf '%s\n' "$tmp" > "$OPF"
else
  python3 -c "import json,sys; d=json.load(open('$OPF')); d['$LABEL']='human'; json.dump(d,open('$OPF','w'),indent=0)"
fi

# --- 6. rebuild the lineage node table, then auto-add its parent->child edges --
#     build_lineage_auto writes the NODES (results/lineage_auto.json); add_lineage_edges
#     appends this run's uses-adapter + builds-on EDGES (results/lineage_prose.json) so the
#     lineage.html page is fully up to date after every experiment — no manual edge step.
python3 "$AR/build_lineage_auto.py"      || echo "[record] WARN: build_lineage_auto failed"
python3 "$PKG/add_lineage_edges.py" "$LABEL" || echo "[record] WARN: add_lineage_edges failed"

echo "[record] DONE $LABEL ($KEPT) — runs.jsonl, pipeline spec, operator/type, lineage node + edges all updated."
