#!/usr/bin/env bash
# Autonomous autoresearch loop for fm-ramble-to-tasks (forked from FMDiscovery).
# Each sample: a headless Claude Code agent reviews, ideates, codes ONE new
# config, builds, and runs ONE program (which self-judges via Sonnet and logs).
# The wrapper enforces the guardrails that make it safe to run unattended.
#
# Usage:
#   ./autoresearch/run.sh [TARGET_TOTAL_EXPERIMENTS]
#   CODER_MODEL=sonnet PER_ITER_BUDGET=1.50 ./autoresearch/run.sh 50
#
# Stops when results/programs.jsonl reaches TARGET (default 50). Resumable: state
# lives in git + program.md + results/.

set -uo pipefail

REPO="/Users/alexisrondeau/Workshop/tada"
PKG="$REPO/fm-ramble-to-tasks"
AR="$PKG/autoresearch"

TARGET="${1:-50}"
CODER_MODEL="${CODER_MODEL:-opus}"           # newest/most capable coder
# Both per-sample limits are OPTIONAL.
#   PER_ITER_BUDGET: hard $ cap on the coder. Empty (default) = NO cap. Set e.g. 2.00 to cap.
#   PER_ITER_TIMEOUT: wall-clock cap (seconds). Default 600 (10m). Set 0/empty to disable.
#     Raise it for training runs, which take far longer than inference programs.
PER_ITER_BUDGET="${PER_ITER_BUDGET:-}"
PER_ITER_TIMEOUT="${PER_ITER_TIMEOUT:-600}"
PATIENCE="${PATIENCE:-5}"                     # consecutive no-improvement programs before a PIVOT

# Immutable ruler: any agent changes here are reverted every sample.
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

# Count only DEV/FULL programs (the agent's runs); exclude wrapper-run TEST lines.
count() {
  local n
  n=$(jq -r 'select(.subset != "test") | .label' "$PKG/results/programs.jsonl" 2>/dev/null | wc -l)
  echo "${n//[[:space:]]/}"
}

echo "[autoresearch] start: $(count)/$TARGET programs | coder=$CODER_MODEL | budget=${PER_ITER_BUDGET:-none} | timeout=${PER_ITER_TIMEOUT:-none}s"
mkdir -p "$AR" "$PKG/results/pipelines"

# --- Evolutionary-run record -------------------------------------------------
# Each run.sh invocation is one EVOLUTIONARY RUN with its own meta-params (target /
# patience / model). We register it in results/runs.jsonl and stamp every program
# this invocation produces with RUN_ID, so the dashboard can show which run each
# program came from (and its config).
RUNS_REG="$PKG/results/runs.jsonl"
RUN_ID=$(( $(wc -l < "$RUNS_REG" 2>/dev/null || echo 0) + 1 ))
printf '{"id":%d,"started":"%s","target":%s,"patience":%s,"model":"%s"}\n' \
  "$RUN_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TARGET" "$PATIENCE" "$CODER_MODEL" >> "$RUNS_REG"
git -C "$REPO" add "$RUNS_REG" 2>/dev/null; git -C "$REPO" commit -q -m "autoresearch: start evolutionary run #$RUN_ID (target=$TARGET, patience=$PATIENCE, model=$CODER_MODEL)" 2>/dev/null || true
echo "[autoresearch] evolutionary run #$RUN_ID (target=$TARGET, patience=$PATIENCE, model=$CODER_MODEL)"

# Backfill dashboard sidecars for any existing runs (best-effort, idempotent).
for L in $(jq -r '.label' "$PKG/results/programs.jsonl" 2>/dev/null | sort -u); do
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
  echo "[autoresearch] sample $((N+1)) | programs=$N/$TARGET | $(date)"

  # Two-parent lineage + patience: elite (best dev) + inspiration program; PIVOT
  # after PATIENCE no-improvements (drops the elite, continues from inspiration only).
  ELITE=""; ELITE_FIT="0"; INSPIRATION=""; PATIENCE_CNT="0"; PIVOT="0"
  eval "$(python3 "$AR/loop_state.py" "$PATIENCE" 2>/dev/null)"
  echo "[autoresearch] elite=$ELITE ($ELITE_FIT) | inspiration=$INSPIRATION | no-improve streak=$PATIENCE_CNT/$PATIENCE$([ "$PIVOT" = "1" ] && echo '  -> PIVOT')"

  if [ -z "$ELITE" ]; then
    DIRECTIVE="Run ONE autoresearch sample now, following AUTORESEARCH_RULES exactly. This is the FIRST program — no runs exist yet. Create 'prog001' from the stock 'baseline' (single-shot, greedy): one focused, well-reasoned first config. End with a green build and exactly one new logged program for your new config."
  elif [ "$PIVOT" = "1" ]; then
    DIRECTIVE="Run ONE autoresearch sample now, following AUTORESEARCH_RULES exactly. Programs completed so far: $N. *** PIVOT ***: the last $PATIENCE_CNT programs did NOT beat the elite ($ELITE, fitness $ELITE_FIT). Take a step back — DROP the elite approach entirely and try something FUNDAMENTALLY different, continuing ONLY from the inspiration program ($INSPIRATION). Begin your program.md log line and your evaluate --note with 'PIVOT: '. End with a green build and exactly one new logged program for your new config."
  else
    DIRECTIVE="Run ONE autoresearch sample now, following AUTORESEARCH_RULES exactly. Programs completed so far: $N. Build your new config on TWO parents — the current elite ($ELITE, fitness $ELITE_FIT) and the inspiration program ($INSPIRATION): combine the best-known approach with what the latest attempt learned. End with a green build and exactly one new logged program for your new config."
  fi

  # Scoped allowlist (NOT a full permission bypass): read, edit/write files,
  # build, run the eval, inspect. No arbitrary shell, no network, no git — the
  # wrapper owns all git. Unlisted tools are denied (non-interactive => no hang).
  # Assemble the coder command; both per-sample limits are optional.
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
  durms=$(printf '%s' "$result" | jq -r '.duration_ms // empty' 2>/dev/null || echo "")
  iserr=$(printf '%s' "$result" | jq -r '.is_error // "?"' 2>/dev/null || echo "?")
  printf '%s\n' "$result" >> "$AR/samples.log"
  echo "[autoresearch] coder: rc=$rc cost=\$$cost is_error=$iserr $([ "$rc" = 124 ] && echo '(TIMEOUT)')"

  # Enforce ruler immutability — revert any tampering with protected paths.
  git checkout -- "${PROTECTED[@]}" 2>/dev/null || true

  AFTER=$(count)
  if [ "$AFTER" -gt "$N" ]; then
    # A run was logged => the build was green (swift run requires it).
    NEWLABEL=$(tail -1 "$PKG/results/programs.jsonl" | jq -r '.label // empty' 2>/dev/null)
    KEPT=$(tail -1 "$PKG/results/programs.jsonl" | jq -r '.kept // false' 2>/dev/null)
    QUAL=$(tail -1 "$PKG/results/programs.jsonl" | jq -r '.fitness // 0' 2>/dev/null)

    # FINALIZE in ONE step so the program appears COMPLETE the moment it shows up:
    # the run row AND every dashboard sidecar (operator, type, cost, pipeline diagram,
    # two-parent lineage, samples) are produced together, then committed once — instead
    # of the old "row now, sidecars a couple seconds later" split that flashed "—" cells.
    # stamp this program with its evolutionary run id (and pivot flag, if any)
    if [ -n "$NEWLABEL" ]; then
      tmp=$(jq -c --arg l "$NEWLABEL" --argjson r "$RUN_ID" --argjson pv "$PIVOT" \
        'if .label==$l and (.subset//"full")!="test" then .run=$r | (if $pv==1 then .pivot=true else . end) else . end' \
        "$PKG/results/programs.jsonl") && printf '%s\n' "$tmp" > "$PKG/results/programs.jsonl"
    fi
    OPF="$PKG/results/operators.json"; [ -f "$OPF" ] || echo '{}' > "$OPF"
    tmp=$(jq --arg l "$NEWLABEL" '.[$l]="agent"' "$OPF" 2>/dev/null) && printf '%s\n' "$tmp" > "$OPF"
    # duration of this program (coder sample: code + build + eval), in ms
    DURF="$PKG/results/durations.json"; [ -f "$DURF" ] || echo '{}' > "$DURF"
    if [ -n "$durms" ]; then
      tmp=$(jq --arg l "$NEWLABEL" --argjson d "$durms" '.[$l]=$d' "$DURF" 2>/dev/null) && printf '%s\n' "$tmp" > "$DURF"
    fi
    python3 "$AR/gen_pipeline.py" "$NEWLABEL" 2>/dev/null || true
    python3 "$AR/record_lineage.py" "$NEWLABEL" "$ELITE" "$INSPIRATION" "$PIVOT" 2>/dev/null || true
    python3 "$AR/gen_costs.py" 2>/dev/null || true
    python3 "$AR/gen_types.py" 2>/dev/null || true
    python3 "$AR/build_lineage_auto.py" 2>/dev/null || true
    python3 "$AR/gen_samples.py" 2>/dev/null || true
    git add -A "$PKG" 2>/dev/null
    git commit -q -m "autoresearch: program $NEWLABEL (q=$QUAL, kept=$KEPT), finalized (coder \$$cost)" 2>/dev/null || true
    echo "[autoresearch] OK: $NEWLABEL finalized (total=$AFTER, q=$QUAL, kept=$KEPT, coder \$$cost)"
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
    echo "[autoresearch] no new run this sample; reverted agent edits"
  fi
done

echo "[autoresearch] DONE: reached $(count)/$TARGET."
