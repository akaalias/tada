#!/usr/bin/env bash
# Clean re-seed: re-evaluate every config on the NEW metric (0.5·F1+0.25·rubric+0.25·pairwise)
# over the expanded 35-case gold. Errors are CAPTURED (no /dev/null), no set -e so one bad
# config doesn't kill the rest, but each failure is loud.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="/Users/alexisrondeau/Workshop/tada"
[ -f "$REPO/.env" ] && { set -a; source "$REPO/.env"; set +a; }
AR="autoresearch"
CONFIGS="baseline exp001 exp002 exp003 exp004 exp005 exp006 exp007 exp008 exp009 exp010 exp011 exp012"

echo "=== gold: $(ls gold/*.json | wc -l | tr -d ' ') cases ==="
echo "=== dev evals (new metric) ==="
for A in $CONFIGS; do
  echo ">>> $A"
  if ! swift run fmramble evaluate --agent "$A" --subset dev --label "$A" 2>&1 | grep -E "QUALITY|ERROR|error:|logged run|fatal"; then
    echo "!!! $A FAILED"
  fi
done

echo "=== leaderboard (dev) ==="
jq -r 'select(.subset!="test") | [.quality, .label] | @tsv' results/runs.jsonl | sort -rn
BEST=$(jq -r 'select(.subset!="test") | [.quality, .label] | @tsv' results/runs.jsonl | sort -rn | head -1 | cut -f2)
echo "best dev = $BEST"

echo "=== held-out TEST for $BEST ==="
swift run fmramble evaluate --agent "$BEST" --subset test --label "${BEST}_test" 2>&1 | grep -E "QUALITY|logged run" || echo "!!! held-out FAILED"

echo "=== sidecars ==="
for A in $CONFIGS; do python3 "$AR/gen_pipeline.py" "$A" 2>&1 | tail -1; done
printf '{' > results/operators.json
first=1
for A in $CONFIGS; do
  op="agent"; [ "$A" = "baseline" ] && op="human"
  [ $first -eq 1 ] && first=0 || printf ',' >> results/operators.json
  printf '"%s":"%s"' "$A" "$op" >> results/operators.json
done
printf '}\n' >> results/operators.json
python3 "$AR/gen_types.py" 2>&1 | tail -1
python3 "$AR/gen_costs.py" 2>&1 | tail -1
python3 "$AR/build_lineage_auto.py" 2>&1 | tail -1
echo "=== RESEED DONE ==="
