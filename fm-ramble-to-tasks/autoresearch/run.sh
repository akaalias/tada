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
PER_ITER_BUDGET="${PER_ITER_BUDGET:-2.00}"   # hard $ cap on the coder per iteration
PER_ITER_TIMEOUT="${PER_ITER_TIMEOUT:-1800}" # wall-clock cap per iteration (s)

# Immutable ruler: any agent changes here are reverted every iteration.
PROTECTED=(
  "fm-ramble-to-tasks/Sources/EvalBench"
  "fm-ramble-to-tasks/Sources/Contract"
  "fm-ramble-to-tasks/Sources/fmramble"
  "fm-ramble-to-tasks/gold"
  "fm-ramble-to-tasks/Package.swift"
)

cd "$REPO" || exit 1

# --- API key (the candidate is on-device; gold/judge need the key) ---
[ -f "$REPO/.env" ] && { set -a; source "$REPO/.env"; set +a; }
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "[autoresearch] ERROR: ANTHROPIC_API_KEY not set (env or $REPO/.env)"; exit 1
fi

count() { local n; n=$(wc -l < "$PKG/results/runs.jsonl" 2>/dev/null || echo 0); echo "${n//[[:space:]]/}"; }

echo "[autoresearch] start: $(count)/$TARGET experiments | coder=$CODER_MODEL | per-iter cap \$$PER_ITER_BUDGET"
mkdir -p "$AR"

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

  DIRECTIVE="Run ONE autoresearch iteration now, following AUTORESEARCH_RULES exactly. Experiments completed so far: $N. End with a green build and exactly one new logged run for your new config."

  # Scoped allowlist (NOT a full permission bypass): read, edit/write files,
  # build, run the eval, inspect. No arbitrary shell, no network, no git — the
  # wrapper owns all git. Unlisted tools are denied (non-interactive => no hang).
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

  # Enforce ruler immutability — revert any tampering with protected paths.
  git checkout -- "${PROTECTED[@]}" 2>/dev/null || true

  AFTER=$(count)
  if [ "$AFTER" -gt "$N" ]; then
    # A run was logged => the build was green (swift run requires it). Commit progress.
    git add -A "$PKG" 2>/dev/null
    git commit -q -m "autoresearch: experiment logged (total=$AFTER, coder \$$cost)" 2>/dev/null || true
    echo "[autoresearch] OK: new experiment logged (total=$AFTER, coder \$$cost)"
  else
    # No run logged. Revert any half-finished agent edits to keep the tree green.
    git checkout -- "fm-ramble-to-tasks/Sources/SplitAgent" 2>/dev/null || true
    echo "[autoresearch] no new run this iteration; reverted agent edits"
  fi
done

echo "[autoresearch] DONE: reached $(count)/$TARGET."
