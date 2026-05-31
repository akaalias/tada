#!/usr/bin/env bash
# ORPO preference fine-tune on ON-POLICY pairs (chosen=corpus gold, rejected=the
# on-device model's own draft). Same recipe as train_adapter_orpo.sh so the ONLY
# variable vs the failed style-vs-style run is the data. Pairs are pre-built by
# gen_orpo_pairs_onpolicy.py (do NOT regenerate here). GPU/memory-heavy (~2-3h).
#
# Usage:  bash research/FMDiscovery/autoresearch/train_orpo_onpolicy.sh
set -uo pipefail

PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
AR="$PKG/autoresearch"; ADP="$PKG/adapter"
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
[ -d "$TOOLKIT" ] || { echo "toolkit not found at $TOOLKIT"; exit 1; }
DATA="$ADP/data_orpo_onpolicy"
[ -f "$DATA/train.jsonl" ] || { echo "no on-policy pairs at $DATA — run gen_orpo_pairs_onpolicy.py"; exit 1; }

EPOCHS="${EPOCHS:-6}"; LR="${LR:-5e-4}"; BATCH="${BATCH:-2}"; ACCUM="${ACCUM:-2}"
MAXSEQ="${MAXSEQ:-1024}"; LAMBDA="${LAMBDA:-0.2}"; NAME="${NAME:-discovery_orpo_op}"
CKPT="$ADP/checkpoints_onpolicy"

echo "[orpo-op] fresh checkpoint dir $CKPT"
rm -rf "$CKPT"; mkdir -p "$CKPT"

echo "[orpo-op] training (epochs=$EPOCHS lr=$LR batch=$BATCH accum=$ACCUM lambda=$LAMBDA) on on-policy pairs — ~2-3h"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
TOOLKIT="$TOOLKIT" python "$AR/train_adapter_orpo.py" \
    --pairs "$DATA/train.jsonl" --eval-pairs "$DATA/valid.jsonl" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --gradient-accumulation-steps "$ACCUM" --max-sequence-length "$MAXSEQ" \
    --lambda-or "$LAMBDA" --activation-checkpointing \
    --checkpoint-dir "$CKPT"

echo "[orpo-op] exporting epochs 1 and 2"
for ep in 1 2; do
  C="$CKPT/adapter-epoch$ep.pt"
  [ -f "$C" ] || { echo "  no $C, skipping"; continue; }
  ( cd "$TOOLKIT" && python -m export.export_fmadapter \
      --adapter-name "${NAME}_e$ep" --checkpoint "$C" --output-dir "$ADP/exports" )
done
echo "[orpo-op] DONE -> $ADP/exports/${NAME}_e{1,2}.fmadapter"
