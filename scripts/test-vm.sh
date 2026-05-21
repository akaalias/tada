#!/usr/bin/env bash
set -euo pipefail

# Run the test suite inside an isolated macOS VM (tart) so UI/end-to-end tests
# never grab the host's screen. The VM has its own window-server session.
#
# The host repo is mounted into the VM read-only-ish via virtiofs; build output
# goes to a VM-local DerivedData path so nothing pollutes the host checkout.
#
# Usage:
#   scripts/test-vm.sh                 # run all three schemes (unit, integration, UI), headless
#   scripts/test-vm.sh TadaUITests     # run just one scheme
#   TADA_VM_GUI=1 scripts/test-vm.sh   # boot the VM head-full so you can WATCH the run
#                                        in a VM desktop window (interactions stay inside
#                                        that window — they don't touch your real desktop)
#
# Prereqs (installed once): brew install cirruslabs/cli/tart esolitos/ipa/sshpass

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VM_NAME="tada-ci"
IMAGE="ghcr.io/cirruslabs/macos-tahoe-xcode:26.2"
VM_USER="admin"
VM_PASS="admin"
MOUNT_NAME="tada"
VM_REPO="/Volumes/My Shared Files/${MOUNT_NAME}"
if [ "$#" -gt 0 ]; then
  SCHEMES=("$@")
else
  SCHEMES=(TadaTests TadaIntegrationTests TadaUITests)
fi

ssh_vm() {
  sshpass -p "$VM_PASS" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "${VM_USER}@${VM_IP}" "$@"
}

echo "==> Regenerating Xcode project on host (file generation only, no app launch)"
( cd "$REPO_ROOT" && xcodegen generate >/dev/null )

# Clone the base image into a working VM the first time.
if ! tart list --quiet 2>/dev/null | grep -qx "$VM_NAME"; then
  echo "==> Cloning $IMAGE -> $VM_NAME (first run, large download)"
  tart clone "$IMAGE" "$VM_NAME"
fi

# Head-full (TADA_VM_GUI=1) opens a VM desktop window so the run is observable;
# default is headless (--no-graphics) for unattended/CI-style runs. Two explicit
# branches (no array) to stay compatible with macOS's bash 3.2 under `set -u`.
if [ "${TADA_VM_GUI:-0}" = "1" ]; then
  echo "==> Booting VM (head-full — a VM desktop window will open, repo mounted)"
  tart run "$VM_NAME" --dir="${MOUNT_NAME}:${REPO_ROOT}" >/tmp/tada-vm-run.log 2>&1 &
else
  echo "==> Booting VM (headless, repo mounted)"
  tart run "$VM_NAME" --no-graphics --dir="${MOUNT_NAME}:${REPO_ROOT}" >/tmp/tada-vm-run.log 2>&1 &
fi
RUN_PID=$!

cleanup() {
  echo "==> Stopping VM"
  tart stop "$VM_NAME" >/dev/null 2>&1 || true
  wait "$RUN_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Waiting for VM IP"
VM_IP=""
for _ in $(seq 1 60); do
  VM_IP="$(tart ip "$VM_NAME" 2>/dev/null || true)"
  [ -n "$VM_IP" ] && break
  sleep 2
done
[ -n "$VM_IP" ] || { echo "VM never got an IP"; exit 1; }
echo "    VM IP: $VM_IP"

echo "==> Waiting for SSH"
for _ in $(seq 1 60); do
  if ssh_vm "echo ready" >/dev/null 2>&1; then break; fi
  sleep 2
done
ssh_vm "echo ready" >/dev/null 2>&1 || { echo "SSH never came up"; exit 1; }

echo "==> Xcode in VM: $(ssh_vm 'xcodebuild -version | tr "\n" " "')"

# The VM has no developer certificate for the project's team, so build with
# ad-hoc signing and hardened-runtime off — enough to launch & test locally.
SIGN_ARGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM='' ENABLE_HARDENED_RUNTIME=NO"

FAIL=0
for scheme in "${SCHEMES[@]}"; do
  echo ""
  echo "==> Running scheme: $scheme (inside VM)"
  # Capture the REAL xcodebuild exit code via a sentinel (a piped grep would
  # mask it). Shared DerivedData so the app builds once and is reused.
  OUT=$(ssh_vm "cd '$VM_REPO' && xcodebuild test \
      -project Tada.xcodeproj -scheme '$scheme' \
      -destination 'platform=macOS' \
      -derivedDataPath /Users/${VM_USER}/dd \
      $SIGN_ARGS 2>&1; echo \"__XCB_EXIT__:\$?\"")
  printf '%s\n' "$OUT" | grep -E 'Test run with|Executed [0-9]|TEST (SUCCEEDED|FAILED)|error:|Testing failed|✘' | tail -40
  CODE=$(printf '%s\n' "$OUT" | grep -oE '__XCB_EXIT__:[0-9]+' | tail -1 | cut -d: -f2)
  if [ "${CODE:-1}" != "0" ]; then
    echo "    ❌ scheme $scheme FAILED (xcodebuild exit ${CODE:-unknown})"
    FAIL=1
  else
    echo "    ✅ scheme $scheme passed"
  fi
done

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All requested schemes passed inside the VM"
else
  echo "❌ Some schemes failed inside the VM"
fi
exit "$FAIL"
