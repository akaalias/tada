#!/usr/bin/env bash
# Autonomous autoresearch loop (Karpathy-style, code-writing agent).
# Single entry point. Resumable: state lives in git + program.md + results/.
# Each iteration: a headless Claude Code agent reviews, ideates, codes, builds,
# and runs one experiment (which self-judges via Sonnet and logs). The script
# enforces the guardrails that make this safe to run unattended.
#
# Usage:
#   ./autoresearch/run.sh [TARGET_TOTAL_EXPERIMENTS]
#   CODER_MODEL=sonnet PER_ITER_BUDGET=1.50 ./autoresearch/run.sh 200
#
# Stops when results/runs.jsonl reaches TARGET_TOTAL_EXPERIMENTS (default 150).

set -uo pipefail

REPO="/Users/alexisrondeau/Workshop/tada"
PKG="$REPO/research/FMDiscovery"
AR="$PKG/autoresearch"

TARGET="${1:-150}"
CODER_MODEL="${CODER_MODEL:-opus}"          # newest/most capable coder
PER_ITER_BUDGET="${PER_ITER_BUDGET:-2.00}"  # hard $ cap on the coder per iteration
PER_ITER_TIMEOUT="${PER_ITER_TIMEOUT:-1800}" # wall-clock cap per iteration (s)

# Immutable ruler: any agent changes here are reverted every iteration.
PROTECTED=(
  "research/FMDiscovery/Sources/EvalBench"
  "research/FMDiscovery/Sources/Contract"
  "research/FMDiscovery/Sources/fmresearch"
  "research/FMDiscovery/gold"
  "research/FMDiscovery/Package.swift"
)

cd "$REPO" || exit 1

# --- force API-key auth (never silently use a subscription) ---
set -a; source "$REPO/.env"; set +a
unset CLAUDE_CODE_OAUTH_TOKEN || true
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "[autoresearch] ERROR: ANTHROPIC_API_KEY not found in $REPO/.env"; exit 1
fi

count() { local n; n=$(wc -l < "$PKG/results/runs.jsonl" 2>/dev/null || echo 0); echo "${n//[[:space:]]/}"; }

echo "[autoresearch] start: $(count)/$TARGET experiments | coder=$CODER_MODEL | per-iter cap \$$PER_ITER_BUDGET"
mkdir -p "$AR" "$PKG/results/pipelines"

# Backfill pipeline diagrams for any experiments missing one (best-effort).
for L in $(jq -r .label "$PKG/results/runs.jsonl" 2>/dev/null | sort -u); do
  [ -f "$PKG/results/pipelines/$L.json" ] || python3 "$AR/gen_pipeline.py" "$L" || true
done
python3 "$AR/gen_costs.py" 2>/dev/null || true   # backfill per-experiment coder costs

while [ "$(count)" -lt "$TARGET" ]; do
  N=$(count)
  echo "=================================================================="
  echo "[autoresearch] iteration $((N+1)) | experiments=$N/$TARGET | $(date)"

  DIRECTIVE="Run ONE autoresearch iteration now, following AUTORESEARCH_RULES exactly. Experiments completed so far: $N. End with a green build and exactly one new logged run for your new config."

  # Scoped allowlist (NOT a full permission bypass): the agent may only read,
  # edit/write files, build, run the eval, and inspect. No arbitrary shell, no
  # network tools, no git — the wrapper owns all git. Unlisted tools are denied
  # (non-interactive => no hang; the timeout is a backstop).
  result=$(timeout "$PER_ITER_TIMEOUT" claude -p "$DIRECTIVE" \
      --append-system-prompt "$(cat "$AR/AGENT.md")" \
      --bare \
      --allowedTools "Read" "Edit" "Write" "Glob" "Grep" \
        "Bash(swift build:*)" "Bash(swift run:*)" \
        "Bash(ls:*)" "Bash(cat:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(sed:*)" \
      --add-dir "$REPO" \
      --model "$CODER_MODEL" \
      --max-budget-usd "$PER_ITER_BUDGET" \
      --output-format json 2>>"$AR/agent.err")
  rc=$?

  cost=$(printf '%s' "$result" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  iserr=$(printf '%s' "$result" | jq -r '.is_error // "?"' 2>/dev/null || echo "?")
  printf '%s\n' "$result" >> "$AR/iterations.log"
  echo "[autoresearch] coder: rc=$rc cost=\$$cost is_error=$iserr $([ "$rc" = 124 ] && echo '(TIMEOUT)')"

  # 1) Enforce ruler immutability — revert any tampering with protected paths.
  git checkout -- "${PROTECTED[@]}" 2>/dev/null || true
  if ! git diff --quiet -- "${PROTECTED[@]}" 2>/dev/null; then
    echo "[autoresearch] WARNING: protected paths still dirty after revert"
  fi

  AFTER=$(count)
  if [ "$AFTER" -gt "$N" ]; then
    # A run was logged => build was green (swift run requires it).
    # Generate the pipeline diagram for the new experiment, then commit progress.
    NEWLABEL=$(tail -1 "$PKG/results/runs.jsonl" | jq -r .label 2>/dev/null)
    [ -n "$NEWLABEL" ] && python3 "$AR/gen_pipeline.py" "$NEWLABEL" || true
    # Tag the operator: this experiment was written+run by the autonomous agent.
    # (The wrapper owns this write, not the agent; the manual track tags "human".)
    if [ -n "$NEWLABEL" ]; then
      OPF="$PKG/results/operators.json"
      [ -f "$OPF" ] || echo '{}' > "$OPF"
      tmp=$(jq --arg l "$NEWLABEL" '.[$l]="agent"' "$OPF" 2>/dev/null) && printf '%s\n' "$tmp" > "$OPF"
    fi
    git add -A "$PKG" 2>/dev/null
    git commit -q -m "autoresearch: experiment logged (total=$AFTER, coder \$$cost)" 2>/dev/null || true
    python3 "$AR/gen_costs.py" 2>/dev/null || true   # refresh costs.json from the new commit
    echo "[autoresearch] OK: new experiment logged (total=$AFTER, coder \$$cost)"
  else
    # No run logged this iteration. Revert any half-finished agent edits to keep green.
    git checkout -- "research/FMDiscovery/Sources/DiscoveryAgent" 2>/dev/null || true
    echo "[autoresearch] no new run this iteration; reverted agent edits"
  fi
done

echo "[autoresearch] DONE: reached $(count)/$TARGET. See dashboard: http://localhost:8765/dashboard/"
