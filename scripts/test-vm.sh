#!/usr/bin/env bash
set -euo pipefail

# Run the test suite inside an isolated macOS VM (tart) so UI/end-to-end tests
# never grab the host's screen. The VM has its own window-server session.
#
# The host repo is mounted into the VM read-only-ish via virtiofs; build output
# goes to a VM-local DerivedData path so nothing pollutes the host checkout.
#
# Usage:
#   scripts/test-vm.sh                 # run all three schemes (unit, integration, UI)
#   scripts/test-vm.sh TadaUITests     # run just one scheme
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
SCHEMES=("${@:-TadaTests TadaIntegrationTests TadaUITests}")

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

echo "==> Booting VM (headless, repo mounted)"
tart run "$VM_NAME" --no-graphics --dir="${MOUNT_NAME}:${REPO_ROOT}" >/tmp/tada-vm-run.log 2>&1 &
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

FAIL=0
for scheme in $SCHEMES; do
  echo ""
  echo "==> Running scheme: $scheme (inside VM)"
  if ! ssh_vm "cd '$VM_REPO' && xcodebuild test \
      -project Tada.xcodeproj -scheme '$scheme' \
      -destination 'platform=macOS' \
      -derivedDataPath /Users/${VM_USER}/dd-${scheme} \
      -resultBundlePath /Users/${VM_USER}/result-${scheme}.xcresult 2>&1 | \
      grep -E 'Test run with|Executed|TEST (SUCCEEDED|FAILED)|error:|✘' | tail -30"; then
    echo "    scheme $scheme reported failures"
    FAIL=1
  fi
done

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All requested schemes passed inside the VM"
else
  echo "❌ Some schemes failed inside the VM"
fi
exit "$FAIL"
