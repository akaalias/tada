#!/usr/bin/env bash
# EXP-057 — GRPO policy fine-tune of the discovery adapter, end to end.
#
# The first objective in this project that optimises the Sonnet rubric reward DIRECTLY
# (SFT imitated a target; ORPO used an odds-ratio; both plateaued ~0.41 with coverage 3).
# Pipeline (all on THIS Mac — generate/eval need the on-device FM; train needs the venv):
#   1. ROLLOUTS  G diverse on-policy drafts per corpus task   (swift `fmresearch generate` x G, grpo_roll sampler)
#   2. REWARD    Sonnet rubric-mean score per draft           (score_rollouts.py, needs ANTHROPIC_API_KEY)
#   3. DATA      group-relative advantages -> train rows      (build_grpo_data.py)
#   4. TRAIN     warm-start v2a_e1, GRPO policy loss          (train_adapter_grpo.py, ~1-2h)
#   5. EXPORT    each epoch -> discovery_grpo_e{1..3}.fmadapter
#   6. EVAL      (printed) greedy on the frozen-30 ruler       -> logged run = exp057
#
# Each stage is skipped if its output already exists (set FORCE=1 to redo). Tune via env:
#   G=6 LIMIT=150 EPOCHS=3 LR=1e-4 WORKERS=8 BETA_KL=0
# Usage:  ANTHROPIC_API_KEY=... bash research/FMDiscovery/autoresearch/run_grpo.sh
set -uo pipefail

PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
AR="$PKG/autoresearch"; ADP="$PKG/adapter"; RES="$PKG/results"
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
WARM="$ADP/checkpoints_v2a/adapter-epoch1.pt"     # the 0.409 SFT champion
CKPT="${CKPT:-$ADP/checkpoints_grpo}"; DATA="$ADP/data_grpo"

G="${G:-6}"; LIMIT="${LIMIT:-150}"; EPOCHS="${EPOCHS:-3}"; LR="${LR:-1e-4}"
BATCH="${BATCH:-2}"; ACCUM="${ACCUM:-2}"; MAXSEQ="${MAXSEQ:-1024}"
WORKERS="${WORKERS:-8}"; BETA_KL="${BETA_KL:-0}"; FORCE="${FORCE:-0}"; NAME="${NAME:-discovery_grpo}"

[ -d "$TOOLKIT" ] || { echo "toolkit not found at $TOOLKIT"; exit 1; }
[ -f "$WARM" ]    || { echo "warm-start checkpoint missing: $WARM"; exit 1; }
have() { [ "$FORCE" = "0" ] && [ -s "$1" ]; }

# 1. ROLLOUTS — G diverse drafts per task from the champion policy (grpo_roll sampler).
echo "[grpo] 1/5 rollouts — $G samples x $LIMIT tasks via grpo_roll"
ROLL_FILES=()
for k in $(seq 1 "$G"); do
  f="$RES/grpo_roll_k$k.jsonl"; ROLL_FILES+=("$f")
  if have "$f"; then echo "  have $f"; continue; fi
  echo "  draw $k/$G -> results/grpo_roll_k$k.jsonl"
  swift run --package-path "$PKG" fmresearch generate \
      --agent grpo_roll --limit "$LIMIT" --out "grpo_roll_k$k.jsonl" || { echo "generate failed"; exit 1; }
done

# 2. REWARD — Sonnet rubric-mean per draft (drops pairwise, per the project decision).
REW="$RES/grpo_rewards.jsonl"
echo "[grpo] 2/5 reward — judging $((G * LIMIT)) drafts with the ruler rubric"
if have "$REW"; then echo "  have $REW";
else
  [ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "ANTHROPIC_API_KEY not set"; exit 1; }
  python3 "$AR/score_rollouts.py" --drafts "${ROLL_FILES[@]}" --out "$REW" --workers "$WORKERS" \
      || { echo "scoring failed"; exit 1; }
fi

# 3. DATA — group-relative advantages -> train/valid rows.
echo "[grpo] 3/5 data — group-relative advantages -> $DATA"
if have "$DATA/train.jsonl"; then echo "  have $DATA/train.jsonl";
else python3 "$AR/build_grpo_data.py" --rewards "$REW" --out "$DATA" || { echo "build failed"; exit 1; }
fi

# 4+5. TRAIN (warm-start) + EXPORT each epoch.
echo "[grpo] 4/5 train — warm-start v2a_e1, GRPO loss (epochs=$EPOCHS lr=$LR beta_kl=$BETA_KL) — ~1-2h"
rm -rf "$CKPT"; mkdir -p "$CKPT"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
TOOLKIT="$TOOLKIT" python "$AR/train_adapter_grpo.py" \
    --rows "$DATA/train.jsonl" --eval-rows "$DATA/valid.jsonl" --warm-start "$WARM" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --gradient-accumulation-steps "$ACCUM" --max-sequence-length "$MAXSEQ" \
    --beta-kl "$BETA_KL" --activation-checkpointing --checkpoint-dir "$CKPT" \
    || { echo "training failed"; exit 1; }

echo "[grpo] 5/5 export epochs 1..$EPOCHS"
for ep in $(seq 1 "$EPOCHS"); do
  C="$CKPT/adapter-epoch$ep.pt"
  [ -f "$C" ] || { echo "  no $C, skipping"; continue; }
  ( cd "$TOOLKIT" && python -m export.export_fmadapter \
      --adapter-name "${NAME}_e$ep" --checkpoint "$C" --output-dir "$ADP/exports" )
done

cat <<EOF

[grpo] DONE. Exports -> $ADP/exports/${NAME}_e{1..$EPOCHS}.fmadapter
Now EVAL each on the frozen-30 ruler (greedy) and log the best as exp057:
  for ep in 1 2 3; do
    swift run --package-path "$PKG" fmresearch evaluate \\
      --agent adapter_grpo_e\$ep --subset full --label adapter_grpo_e\$ep \\
      --note "exp057 GRPO judge-reward policy FT, warm-start v2a_e1, epoch \$ep"
  done
Champion to beat: adapter_v2a_e1 = 0.409 (full-30 greedy). Delta <=0.03 is noise.
GRPO weights are gitignored (*.pt, exports/); move checkpoints_grpo/ to ~/tada-adapter-weights/ before pushing.
EOF
