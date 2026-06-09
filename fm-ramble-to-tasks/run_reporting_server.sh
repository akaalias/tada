#!/usr/bin/env bash
# Serve the autoresearch dashboard (no-cache static server) in the foreground.
# Run this in its own shell; Ctrl-C to stop.
#
# Usage:
#   ./run_reporting_server.sh [PORT]      # default 8766
set -euo pipefail

cd "$(dirname "$0")"
PORT="${1:-8766}"

echo "dashboard:  http://localhost:${PORT}/dashboard/"
echo "(Ctrl-C to stop)"
exec python3 dashboard/serve.py "$PORT"
