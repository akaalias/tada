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
TOOLKIT="${TOOLKIT:?Set TOOLKIT=/path/to/adapter_training_toolkit_v26 (download from Apple Developer)}"
EPOCHS="${EPOCHS:-5}"; LR="${LR:-1e-3}"; BATCH="${BATCH:-4}"; NAME="${NAME:-discovery_v1}"

echo "[adapter] 1/4 formatting training data from corpus/"
python3 "$AR/format_training_data.py"

echo "[adapter] 2/4 python 3.11 venv + toolkit requirements"
PY311="$(pyenv root 2>/dev/null)/versions/3.11.9/bin/python3"
[ -x "$PY311" ] || PY311="python3"   # fall back; toolkit prefers 3.11
"$PY311" -m venv "$ADP/venv"
# shellcheck disable=SC1091
source "$ADP/venv/bin/activate"
pip install -q --upgrade pip
pip install -q -r "$TOOLKIT/requirements.txt"

echo "[adapter] 3/4 training (epochs=$EPOCHS lr=$LR batch=$BATCH) — this takes a while"
( cd "$TOOLKIT" && python -m examples.train_adapter \
    --train-data "$ADP/data/train.jsonl" \
    --eval-data  "$ADP/data/valid.jsonl" \
    --epochs "$EPOCHS" --learning-rate "$LR" --batch-size "$BATCH" \
    --checkpoint-dir "$ADP/checkpoints" )

echo "[adapter] 4/4 exporting .fmadapter"
( cd "$TOOLKIT" && python -m export.export_fmadapter \
    --adapter-name "$NAME" \
    --checkpoint "$ADP/checkpoints/adapter-final.pt" \
    --output-dir "$ADP/exports" )

echo "[adapter] DONE -> $ADP/exports/$NAME.fmadapter"
echo "[adapter] next: stop run.sh, tell Claude to wire the adapter knob, then restart."
