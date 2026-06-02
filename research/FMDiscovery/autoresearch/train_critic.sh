#!/usr/bin/env bash
# Train the pointwise COVERAGE CRITIC adapter (#1) — plain SFT on (task+7 questions ->
# coverage digit), reusing the toolkit example trainer wholesale (same path as the SFT
# planner adapters, only the data differs). Data is pre-built by format_critic_data.py.
#
# Usage:  bash research/FMDiscovery/autoresearch/train_critic.sh
set -uo pipefail
PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
ADP="$PKG/adapter"
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
DATA="${DATA:-$ADP/data_critic}"; CKPT="${CKPT:-$ADP/checkpoints_critic}"
EPOCHS="${EPOCHS:-6}"; LR="${LR:-5e-4}"; BATCH="${BATCH:-4}"; ACCUM="${ACCUM:-1}"; NAME="${NAME:-discovery_critic}"
[ -d "$TOOLKIT" ] || { echo "toolkit not found at $TOOLKIT"; exit 1; }
[ -f "$DATA/train.jsonl" ] || { echo "no critic data — run format_critic_data.py"; exit 1; }

echo "[critic] fresh checkpoint dir $CKPT"; rm -rf "$CKPT"; mkdir -p "$CKPT"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
echo "[critic] SFT (epochs=$EPOCHS lr=$LR batch=$BATCH accum=$ACCUM) on $(wc -l <"$DATA/train.jsonl") examples"
( cd "$TOOLKIT" && python -m examples.train_adapter \
    --train-data "$DATA/train.jsonl" --eval-data "$DATA/valid.jsonl" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --gradient-accumulation-steps "$ACCUM" --activation-checkpointing \
    --checkpoint-dir "$CKPT" ) || { echo "training failed"; exit 1; }

echo "[critic] exporting epochs (the gate uses the .pt directly; export is for on-device use)"
for ep in $(seq 1 "$EPOCHS"); do
  C="$CKPT/adapter-epoch$ep.pt"
  [ -f "$C" ] || continue
  ( cd "$TOOLKIT" && python -m export.export_fmadapter --adapter-name "${NAME}_e$ep" \
      --checkpoint "$C" --output-dir "$ADP/exports" ) 2>/dev/null
done
echo "[critic] DONE -> checkpoints at $CKPT (run critic_gate.py next)"
