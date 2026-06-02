# require_ac_power.sh — source this at the top of any long GPU/training script.
# Heavy MPS training is a sustained load that flattens the battery; a dead battery
# once force-rebooted the Mac mid-run and lost an epoch. Refuse to start on battery
# unless explicitly overridden with ALLOW_BATTERY=1.
if ! pmset -g batt 2>/dev/null | grep -q "AC Power"; then
  pct="$(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1)"
  if [ "${ALLOW_BATTERY:-0}" = "1" ]; then
    echo "[power] WARNING: on BATTERY ($pct), ALLOW_BATTERY=1 — proceeding; plug in soon."
  else
    echo "[power] On BATTERY power ($pct). Training would drain it and risk a hard-reboot mid-run."
    echo "[power] Plug in the laptop, or set ALLOW_BATTERY=1 to override."
    exit 1
  fi
else
  echo "[power] AC power OK ($(pmset -g batt 2>/dev/null | grep -oE '[0-9]+%' | head -1) battery)."
fi
