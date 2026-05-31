#!/usr/bin/env bash
# ask.sh "<your task>" [config]
# Run the on-device discovery model on a raw task and print the 7 clarifying
# questions. Pure on-device (Apple FM + LoRA adapter) — no cloud, no judge.
# Default config is exp056 (the current best, 0.44). e.g.:
#   ./research/FMDiscovery/ask.sh "start a weekly newsletter"
set -euo pipefail
swift run --package-path "$(dirname "$0")" fmresearch inspect "${1:?usage: ask.sh \"<task>\" [config]}" --agent "${2:-exp056}"
