#!/usr/bin/env bash
set -Eeuo pipefail

# Run the test against the checked-out project, but keep all fixtures isolated
# in a temporary directory so no real game or LiveSplit installation is needed.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
PID=""

# Always stop the fake game process and remove the test files, even on failure.
cleanup() {
  [[ -z "$PID" ]] || {
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  }
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/bin" "$TMP/LiveSplit" "$TMP/pfx"
touch "$TMP/LiveSplit/LiveSplit.exe"

# Replace sudo with a recorder. This lets the test inspect the exact namespace
# command without requesting privileges or changing the host system.
cat > "$TMP/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$TEST_LOG"
MOCK
chmod +x "$TMP/bin/sudo"

# Give the fake process the environment markers used by the launcher to
# recognize Proton/Wine games, and give it a recognizable Windows command name.
WINEPREFIX="$TMP/pfx"
WINELOADER="$(type -P true)"
TEST_LOG="$TMP/log"
export WINEPREFIX WINELOADER TEST_LOG

bash -c 'exec -a /tmp/LiveSplitProtonTest.exe sleep 60' >/dev/null 2>&1 &
PID=$!
sleep .2

# Select the only candidate and capture the launcher's user-facing output.
out="$(printf '1\n' | PATH="$TMP/bin:$PATH" "$ROOT/livesplit-proton-launcher.sh" --livesplit "$TMP/LiveSplit/LiveSplit.exe")"

# Verify process selection and the important nsenter / environment arguments.
[[ "$out" == *"Selected: /tmp/LiveSplitProtonTest.exe"* ]]
grep -Fq '<nsenter>' "$TEST_LOG"
grep -Fq "<$PID>" "$TEST_LOG"
grep -Fq '<--setuid>' "$TEST_LOG"
grep -Fq '<WINESERVERSOCKET>' "$TEST_LOG"
grep -Fq '<LD_PRELOAD>' "$TEST_LOG"
grep -Fq "<$TMP/LiveSplit/LiveSplit.exe>" "$TEST_LOG"

printf 'Launcher smoke test passed.\n'
