#!/usr/bin/env bash
# ORPO preference fine-tuning of the 3B LoRA adapter (judgment transfer).
# Mirrors train_adapter.sh but uses the custom ORPO trainer + ORPO pair data.
# GPU/memory-heavy (2 forward passes/batch) — do NOT run concurrently with run.sh.
#
# Usage:
#   EPOCHS=6 LR=5e-4 LAMBDA=0.2 NAME=discovery_orpo \
#     bash research/FMDiscovery/autoresearch/train_adapter_orpo.sh
set -uo pipefail

PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
AR="$PKG/autoresearch"
ADP="$PKG/adapter"
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
[ -d "$TOOLKIT" ] || { echo "toolkit not found at $TOOLKIT"; exit 1; }

EPOCHS="${EPOCHS:-6}"; LR="${LR:-5e-4}"; BATCH="${BATCH:-2}"; ACCUM="${ACCUM:-2}"
MAXSEQ="${MAXSEQ:-1024}"; LAMBDA="${LAMBDA:-0.2}"; NAME="${NAME:-discovery_orpo}"

echo "[orpo] 1/3 building ORPO coverage-contrast pairs"
python3 "$AR/gen_orpo_pairs.py"

echo "[orpo] 2/3 training (epochs=$EPOCHS lr=$LR batch=$BATCH accum=$ACCUM lambda=$LAMBDA) — heavy, ~2h"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
TOOLKIT="$TOOLKIT" python "$AR/train_adapter_orpo.py" \
    --pairs "$ADP/data_orpo/train.jsonl" \
    --eval-pairs "$ADP/data_orpo/valid.jsonl" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --gradient-accumulation-steps "$ACCUM" --max-sequence-length "$MAXSEQ" \
    --lambda-or "$LAMBDA" --activation-checkpointing \
    --checkpoint-dir "$ADP/checkpoints"

echo "[orpo] 3/3 exporting best epochs (epoch1, epoch2) — early checkpoints generalise best here"
for ep in 1 2; do
  CKPT="$ADP/checkpoints/adapter-epoch$ep.pt"
  [ -f "$CKPT" ] || { echo "  no $CKPT, skipping"; continue; }
  ( cd "$TOOLKIT" && python -m export.export_fmadapter \
      --adapter-name "${NAME}_e$ep" --checkpoint "$CKPT" --output-dir "$ADP/exports" )
done
echo "[orpo] DONE -> $ADP/exports/${NAME}_e{1,2}.fmadapter"
echo "[orpo] next: add configs adapter_orpo_e1/e2 in Configs.swift, eval --subset full greedy"
