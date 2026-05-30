#!/usr/bin/env bash
# Train a LoRA adapter for the on-device model from the corpus demonstration bank.
#
# Prereq: download Apple's Foundation Models Adapter Training Toolkit (Apple ID):
#   https://developer.apple.com/download/foundation-models-adapter/
# Then:
#   TOOLKIT=/path/to/adapter_training_toolkit_v26 ./research/FMDiscovery/autoresearch/train_adapter.sh
#
# Outputs research/FMDiscovery/adapter/exports/discovery_v1.fmadapter
set -euo pipefail

PKG="/Users/alexisrondeau/Workshop/tada/research/FMDiscovery"
AR="$PKG/autoresearch"
ADP="$PKG/adapter"
# Default to the toolkit unzipped inside the package; override with TOOLKIT=...
TOOLKIT="${TOOLKIT:-$PKG/adapter_training_toolkit_v26_0_0}"
[ -d "$TOOLKIT" ] || { echo "toolkit not found at $TOOLKIT (set TOOLKIT=/path)"; exit 1; }
EPOCHS="${EPOCHS:-6}"; LR="${LR:-1e-3}"; BATCH="${BATCH:-4}"; NAME="${NAME:-discovery_v1}"
# Memory-frugal knobs (this toolkit is memory-hungry on Mac; activation checkpointing on
# by default to avoid swap-thrashing). ACCUM keeps effective batch = BATCH*ACCUM.
ACCUM="${ACCUM:-1}"; MAXSEQ="${MAXSEQ:-}"; ACTCKPT="${ACTCKPT:-1}"

echo "[adapter] 1/4 formatting training data from corpus/"
python3 "$AR/format_training_data.py"

echo "[adapter] 2/4 python 3.11 venv + toolkit requirements"
PY311="$(pyenv root 2>/dev/null)/versions/3.11.9/bin/python3"
[ -x "$PY311" ] || PY311="python3"   # fall back; toolkit prefers 3.11
[ -d "$ADP/venv" ] || "$PY311" -m venv "$ADP/venv"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
# Idempotent + network-resilient: skip if deps already import; retry on flaky net.
if python -c "import torch, coremltools, tamm" 2>/dev/null; then
  echo "[adapter] deps already installed — skipping"
else
  pip install --upgrade pip
  pip install --retries 10 --timeout 120 -r "$TOOLKIT/requirements.txt"
fi

echo "[adapter] 3/4 training (epochs=$EPOCHS lr=$LR batch=$BATCH accum=$ACCUM maxseq=${MAXSEQ:-none} actckpt=$ACTCKPT) — this takes a while"
extra=( --gradient-accumulation-steps "$ACCUM" )
[ "$ACTCKPT" = "1" ] && extra+=( --activation-checkpointing )
[ -n "$MAXSEQ" ] && extra+=( --max-sequence-length "$MAXSEQ" )
( cd "$TOOLKIT" && python -m examples.train_adapter \
    --train-data "$ADP/data/train.jsonl" \
    --eval-data  "$ADP/data/valid.jsonl" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    "${extra[@]}" \
    --checkpoint-dir "$ADP/checkpoints" )

echo "[adapter] 4/4 exporting .fmadapter"
CKPT="$(ls -t "$ADP/checkpoints"/*.pt 2>/dev/null | head -1)"
[ -n "$CKPT" ] || { echo "no checkpoint .pt found in $ADP/checkpoints"; exit 1; }
echo "[adapter] using checkpoint: $CKPT"
( cd "$TOOLKIT" && python -m export.export_fmadapter \
    --adapter-name "$NAME" \
    --checkpoint "$CKPT" \
    --output-dir "$ADP/exports" )

echo "[adapter] DONE -> $ADP/exports/$NAME.fmadapter"
echo "[adapter] next: stop run.sh, tell Claude to wire the adapter knob, then restart."
