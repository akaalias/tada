#!/usr/bin/env bash
# EXP-059 — GAD (Generative Adversarial Distillation), round 0.
#
# The one method whose mechanism addresses what GRPO could not: the reward comes from a
# DISCRIMINATOR trained to tell TEACHER (Sonnet gold) sets from STUDENT drafts, so the
# signal is grounded in the teacher (which DOES contain the missing unknown), not in the
# student's own flat-coverage drafts. The policy update is the SAME group-relative GRPO
# gradient — only the reward source changes (D-score instead of judge rubric).
#
# Reuses cached rollouts; reward = gad_discriminator.py (already written to gad_rewards.jsonl
# if present). Stages skip if their output exists (FORCE=1 to redo). Tunables:
#   EPOCHS=2 LR=1e-4 BETA_KL=1.0
# Usage:  bash research/FMDiscovery/autoresearch/run_gad.sh
set -uo pipefail

PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
AR="$PKG/autoresearch"; ADP="$PKG/adapter"; RES="$PKG/results"
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
WARM="$ADP/checkpoints_v2a/adapter-epoch1.pt"
CKPT="${CKPT:-$ADP/checkpoints_gad}"; DATA="$ADP/data_gad"; REW="$RES/gad_rewards.jsonl"
EPOCHS="${EPOCHS:-2}"; LR="${LR:-1e-4}"; BATCH="${BATCH:-2}"; ACCUM="${ACCUM:-2}"
MAXSEQ="${MAXSEQ:-1024}"; BETA_KL="${BETA_KL:-1.0}"; NAME="${NAME:-discovery_gad}"; FORCE="${FORCE:-0}"
[ -d "$TOOLKIT" ] || { echo "toolkit not found"; exit 1; }
[ -f "$WARM" ] || { echo "warm-start missing: $WARM"; exit 1; }
have() { [ "$FORCE" = "0" ] && [ -s "$1" ]; }

# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"

# 1. REWARD — train the discriminator and score every rollout draft (D = teacher-likeness).
echo "[gad] 1/4 reward — embedding-MLP discriminator over gold-vs-draft sets"
if have "$REW"; then echo "  have $REW";
else python "$AR/gad_discriminator.py" --out "$REW" || { echo "discriminator failed"; exit 1; }
fi

# 2. DATA — group-relative advantages over the D-scores (same builder as GRPO).
echo "[gad] 2/4 data — advantages over D-scores -> $DATA"
if have "$DATA/train.jsonl"; then echo "  have $DATA/train.jsonl";
else python "$AR/build_grpo_data.py" --rewards "$REW" --out "$DATA" || { echo "build failed"; exit 1; }
fi

# 3. TRAIN — same KL-anchored GRPO policy gradient, reward = D-score (warm-start v2a_e1).
echo "[gad] 3/4 train — warm-start v2a_e1, GAD reward, KL anchor (epochs=$EPOCHS lr=$LR beta_kl=$BETA_KL)"
rm -rf "$CKPT"; mkdir -p "$CKPT"
TOOLKIT="$TOOLKIT" python "$AR/train_adapter_grpo.py" \
    --rows "$DATA/train.jsonl" --eval-rows "$DATA/valid.jsonl" --warm-start "$WARM" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --gradient-accumulation-steps "$ACCUM" --max-sequence-length "$MAXSEQ" \
    --beta-kl "$BETA_KL" --activation-checkpointing --checkpoint-dir "$CKPT" \
    || { echo "training failed"; exit 1; }

# 4. EXPORT each epoch.
echo "[gad] 4/4 export epochs 1..$EPOCHS"
for ep in $(seq 1 "$EPOCHS"); do
  C="$CKPT/adapter-epoch$ep.pt"
  [ -f "$C" ] || { echo "  no $C, skipping"; continue; }
  ( cd "$TOOLKIT" && python -m export.export_fmadapter \
      --adapter-name "${NAME}_e$ep" --checkpoint "$C" --output-dir "$ADP/exports" )
done

cat <<EOF

[gad] DONE. Exports -> $ADP/exports/${NAME}_e{1..$EPOCHS}.fmadapter
EVAL on the frozen-30 ruler (greedy) and log the best as exp059:
  for ep in 1 2; do
    swift run --package-path "$PKG" fmresearch evaluate \\
      --agent adapter_gad_e\$ep --subset full --label adapter_gad_e\$ep \\
      --note "exp059 GAD round-0, discriminator reward, warm-start v2a_e1, epoch \$ep"
  done
Champion to beat: adapter_v2a_e1 = 0.409 (full-30 greedy). Watch coverage (3?->4).
EOF
