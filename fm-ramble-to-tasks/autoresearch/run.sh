#!/usr/bin/env bash
# Autonomous autoresearch loop for fm-ramble-to-tasks (forked from FMDiscovery).
# Each iteration: a headless Claude Code agent reviews, ideates, codes ONE new
# config, builds, and runs ONE experiment (which self-judges via Sonnet and logs).
# The wrapper enforces the guardrails that make it safe to run unattended.
#
# Usage:
#   ./autoresearch/run.sh [TARGET_TOTAL_EXPERIMENTS]
#   CODER_MODEL=sonnet PER_ITER_BUDGET=1.50 ./autoresearch/run.sh 50
#
# Stops when results/runs.jsonl reaches TARGET (default 50). Resumable: state
# lives in git + program.md + results/.

set -uo pipefail

REPO="/Users/alexisrondeau/Workshop/tada"
PKG="$REPO/fm-ramble-to-tasks"
AR="$PKG/autoresearch"

TARGET="${1:-50}"
CODER_MODEL="${CODER_MODEL:-opus}"           # newest/most capable coder
# Both per-iteration limits are OPTIONAL.
#   PER_ITER_BUDGET: hard $ cap on the coder. Empty (default) = NO cap. Set e.g. 2.00 to cap.
#   PER_ITER_TIMEOUT: wall-clock cap (seconds). Default 600 (10m). Set 0/empty to disable.
#     Raise it for training runs, which take far longer than inference experiments.
PER_ITER_BUDGET="${PER_ITER_BUDGET:-}"
PER_ITER_TIMEOUT="${PER_ITER_TIMEOUT:-600}"
PATIENCE="${PATIENCE:-5}"                     # consecutive no-improvement experiments before a PIVOT

# Immutable ruler: any agent changes here are reverted every iteration.
PROTECTED=(
  "fm-ramble-to-tasks/Sources/EvalBench"
  "fm-ramble-to-tasks/Sources/Contract"
  "fm-ramble-to-tasks/Sources/fmramble"
  "fm-ramble-to-tasks/gold"
  "fm-ramble-to-tasks/Package.swift"
  "fm-ramble-to-tasks/dashboard"
)

cd "$REPO" || exit 1

# --- API key (the candidate is on-device; gold/judge need the key) ---
[ -f "$REPO/.env" ] && { set -a; source "$REPO/.env"; set +a; }
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "[autoresearch] ERROR: ANTHROPIC_API_KEY not set (env or $REPO/.env)"; exit 1
fi

# Count only DEV/FULL experiments (the agent's runs); exclude wrapper-run TEST lines.
count() {
  local n
  n=$(jq -r 'select(.subset != "test") | .label' "$PKG/results/runs.jsonl" 2>/dev/null | wc -l)
  echo "${n//[[:space:]]/}"
}

echo "[autoresearch] start: $(count)/$TARGET experiments | coder=$CODER_MODEL | budget=${PER_ITER_BUDGET:-none} | timeout=${PER_ITER_TIMEOUT:-none}s"
mkdir -p "$AR" "$PKG/results/pipelines"

# Backfill dashboard sidecars for any existing runs (best-effort, idempotent).
for L in $(jq -r '.label' "$PKG/results/runs.jsonl" 2>/dev/null | sort -u); do
  [ -f "$PKG/results/pipelines/$L.json" ] || python3 "$AR/gen_pipeline.py" "$L" 2>/dev/null || true
done
python3 "$AR/gen_costs.py" 2>/dev/null || true
python3 "$AR/gen_types.py" 2>/dev/null || true
python3 "$AR/build_lineage_auto.py" 2>/dev/null || true
python3 "$AR/gen_samples.py" 2>/dev/null || true

while [ "$(count)" -lt "$TARGET" ]; do
  # --- Training-track gate ---------------------------------------------------
  # The agent can request the out-of-scope TRAINING track (a fine-tuned LoRA
  # adapter) by writing autoresearch/REQUEST.md. For now we PAUSE on it.
  # (Phase 3 replaces this pause with the autonomous RunPod training driver.)
  if [ -f "$AR/REQUEST.md" ]; then
    echo "=================================================================="
    echo "[autoresearch] PAUSED — agent requested the training track:"
    echo "------------------------------------------------------------------"
    cat "$AR/REQUEST.md"
    echo "------------------------------------------------------------------"
    echo "[autoresearch] To resume: handle the request, add a Configs.swift entry for the"
    echo "               new adapter, update program.md current-best, then"
    echo "               'rm $AR/REQUEST.md' and re-run ./autoresearch/run.sh"
    exit 0
  fi

  N=$(count)
  echo "=================================================================="
  echo "[autoresearch] iteration $((N+1)) | experiments=$N/$TARGET | $(date)"

  # Two-parent lineage + patience: champion (best dev) + previous experiment; PIVOT
  # after PATIENCE no-improvements (drops the champion, continues from previous only).
  CHAMP=""; CHAMPQ="0"; PREV=""; PATIENCE_CNT="0"; PIVOT="0"
  eval "$(python3 "$AR/loop_state.py" "$PATIENCE" 2>/dev/null)"
  echo "[autoresearch] champion=$CHAMP ($CHAMPQ) | previous=$PREV | no-improve streak=$PATIENCE_CNT/$PATIENCE$([ "$PIVOT" = "1" ] && echo '  -> PIVOT')"

  if [ "$PIVOT" = "1" ]; then
    DIRECTIVE="Run ONE autoresearch iteration now, following AUTORESEARCH_RULES exactly. Experiments completed so far: $N. *** PIVOT ***: the last $PATIENCE_CNT experiments did NOT beat the champion ($CHAMP, quality $CHAMPQ). Take a step back — DROP the champion approach entirely and try something FUNDAMENTALLY different, continuing ONLY from the previous experiment ($PREV). Begin your program.md log line and your evaluate --note with 'PIVOT: '. End with a green build and exactly one new logged run for your new config."
  else
    DIRECTIVE="Run ONE autoresearch iteration now, following AUTORESEARCH_RULES exactly. Experiments completed so far: $N. Build your new config on TWO parents — the current champion ($CHAMP, quality $CHAMPQ) and the previous experiment ($PREV): combine the best-known approach with what the latest attempt learned. End with a green build and exactly one new logged run for your new config."
  fi

  # Scoped allowlist (NOT a full permission bypass): read, edit/write files,
  # build, run the eval, inspect. No arbitrary shell, no network, no git — the
  # wrapper owns all git. Unlisted tools are denied (non-interactive => no hang).
  # Assemble the coder command; both per-iteration limits are optional.
  claude_cmd=(claude -p "$DIRECTIVE"
      --append-system-prompt "$(cat "$AR/AGENT.md")"
      --bare
      --allowedTools "Read" "Edit" "Write" "Glob" "Grep"
        "Bash(swift build:*)" "Bash(swift run:*)"
        "Bash(ls:*)" "Bash(cat:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(sed:*)"
      --add-dir "$REPO"
      --model "$CODER_MODEL"
      --output-format json)
  [ -n "$PER_ITER_BUDGET" ] && claude_cmd+=(--max-budget-usd "$PER_ITER_BUDGET")

  if [ -n "$PER_ITER_TIMEOUT" ] && [ "$PER_ITER_TIMEOUT" != "0" ]; then
    result=$(timeout "$PER_ITER_TIMEOUT" "${claude_cmd[@]}" 2>>"$AR/agent.err")
  else
    result=$("${claude_cmd[@]}" 2>>"$AR/agent.err")
  fi
  rc=$?

  cost=$(printf '%s' "$result" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  iserr=$(printf '%s' "$result" | jq -r '.is_error // "?"' 2>/dev/null || echo "?")
  printf '%s\n' "$result" >> "$AR/iterations.log"
  echo "[autoresearch] coder: rc=$rc cost=\$$cost is_error=$iserr $([ "$rc" = 124 ] && echo '(TIMEOUT)')"

  # Enforce ruler immutability — revert any tampering with protected paths.
  git checkout -- "${PROTECTED[@]}" 2>/dev/null || true

  AFTER=$(count)
  if [ "$AFTER" -gt "$N" ]; then
    # A run was logged => the build was green (swift run requires it). Commit progress.
    NEWLABEL=$(tail -1 "$PKG/results/runs.jsonl" | jq -r '.label // empty' 2>/dev/null)
    KEPT=$(tail -1 "$PKG/results/runs.jsonl" | jq -r '.kept // false' 2>/dev/null)
    # Stamp the pivot flag onto the experiment's own record so the dashboard chart +
    # table can mark it (the lineage graph reads it from lineage_meta.json via record_lineage).
    if [ "$PIVOT" = "1" ] && [ -n "$NEWLABEL" ]; then
      tmp=$(jq -c --arg l "$NEWLABEL" 'if .label==$l and (.subset//"full")!="test" then .pivot=true else . end' "$PKG/results/runs.jsonl") \
        && printf '%s\n' "$tmp" > "$PKG/results/runs.jsonl"
    fi
    git add -A "$PKG" 2>/dev/null
    git commit -q -m "autoresearch: experiment logged (total=$AFTER, coder \$$cost)" 2>/dev/null || true
    echo "[autoresearch] OK: new experiment logged (total=$AFTER, coder \$$cost)"
    # Dashboard sidecars (auto): pipeline diagram, operator tag, cost / type / lineage.
    python3 "$AR/gen_pipeline.py" "$NEWLABEL" 2>/dev/null || true
    OPF="$PKG/results/operators.json"; [ -f "$OPF" ] || echo '{}' > "$OPF"
    tmp=$(jq --arg l "$NEWLABEL" '.[$l]="agent"' "$OPF" 2>/dev/null) && printf '%s\n' "$tmp" > "$OPF"
    python3 "$AR/record_lineage.py" "$NEWLABEL" "$CHAMP" "$PREV" "$PIVOT" 2>/dev/null || true
    python3 "$AR/gen_costs.py" 2>/dev/null || true
    python3 "$AR/gen_types.py" 2>/dev/null || true
    python3 "$AR/build_lineage_auto.py" 2>/dev/null || true
    git add -A "$PKG" 2>/dev/null
    git commit -q -m "autoresearch: dashboard sidecars for $NEWLABEL" 2>/dev/null || true
    # Wrapper-run held-out TEST check on a new DEV best — REPORTING ONLY. The coder
    # agent never runs test, never sees these results, and must not tune toward them.
    # This keeps the honesty check automatic without contaminating the optimization.
    if [ "$KEPT" = "true" ] && [ -n "$NEWLABEL" ]; then
      echo "[autoresearch] new dev best ($NEWLABEL) — running held-out TEST check"
      swift run --package-path "$PKG" fmramble evaluate --agent "$NEWLABEL" --subset test --label "${NEWLABEL}_test" >/dev/null 2>>"$AR/agent.err" || true
      git add -A "$PKG" 2>/dev/null
      git commit -q -m "autoresearch: held-out test for $NEWLABEL" 2>/dev/null || true
    fi
  else
    # No run logged. Revert any half-finished agent edits to keep the tree green.
    git checkout -- "fm-ramble-to-tasks/Sources/SplitAgent" 2>/dev/null || true
    echo "[autoresearch] no new run this iteration; reverted agent edits"
  fi
done

echo "[autoresearch] DONE: reached $(count)/$TARGET."
