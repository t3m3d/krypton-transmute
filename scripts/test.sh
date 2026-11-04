#!/usr/bin/env bash
# Runs the Krypton engine checks and propagates their result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KCC="${KCC:-/usr/local/krypton/bootstrap/kcc_driver_macos_aarch64}"
if [ ! -x "$KCC" ]; then
  KCC="$(command -v kcc || true)"
fi
if [ -z "$KCC" ] || [ ! -x "$KCC" ]; then
  echo "error: kcc not found. Install Krypton or set KCC=/path/to/kcc" >&2
  exit 1
fi

# Krypton's `exit` does not propagate a status through `kcc -r`, so the
# harness reads the summary line instead of trusting the exit code.
set +e
OUTPUT="$("$KCC" -r "$ROOT/src/engine_test.ks" 2>&1)"
STATUS=$?
set -e

printf '%s\n' "$OUTPUT"

if [ "$STATUS" -ne 0 ]; then
  echo "error: kcc exited with status $STATUS" >&2
  exit "$STATUS"
fi

if printf '%s' "$OUTPUT" | grep -q "checks failed"; then
  exit 1
fi

exit 0
