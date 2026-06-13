#!/usr/bin/env bash
# Integration tests for pi-box BASH function
# Tests verify observable CLI behavior through the public function interface.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_BOX_SH="$SCRIPT_DIR/../pi-box.sh"

# ---- test harness ----

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (output did not contain '$needle')"
    echo "  output was: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

summary() {
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
}

# ---- helpers ----

# Create a temp HOME with mock devbox and pi.
# Sets TEST_HOME, HOME, and PATH in the calling scope.
setup_test_env() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/bin"

  # Fake devbox: records invocations
  cat > "$TEST_HOME/bin/devbox" << 'FAKEDEVBOX'
#!/usr/bin/env bash
echo "devbox called with: $*" >> "$HOME/devbox-calls.log"
if [[ "$*" == *"global shellenv --init-hook"* ]]; then
  # Emit shellenv that adds our fake bin to PATH
  echo "export PATH=\"$HOME/bin:\$PATH\""
fi
true
FAKEDEVBOX
  chmod +x "$TEST_HOME/bin/devbox"

  # Fake pi: records invocations and arguments
  cat > "$TEST_HOME/bin/pi" << 'FAKEPI'
#!/usr/bin/env bash
echo "pi called with: $*" >> "$HOME/pi-calls.log"
echo "pi-output: $*"
true
FAKEPI
  chmod +x "$TEST_HOME/bin/pi"

  export PATH="$TEST_HOME/bin:/usr/bin:/bin"
}

# ---- test 1: pi-box "help" activates devbox and runs pi with "help" (tracer bullet) ----

echo ""
echo "=== test 1: pi-box \"help\" activates devbox and runs pi ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Source the function definition
source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?
set -e

assert_exit "pi-box help exits 0" 0 "$EXIT_CODE"
assert_contains "pi receives help argument" "$OUTPUT" "pi-output: help"

# Verify devbox global shellenv was called
if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox global shellenv called" "$DEVCALLS" "global shellenv --init-hook"
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 2: unknown flags pass through to pi ----

echo ""
echo "=== test 2: unknown flags pass through to pi ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box --some-flag value 2>&1)
EXIT_CODE=$?
set -e

assert_exit "unknown flags exits 0" 0 "$EXIT_CODE"
assert_contains "pi receives unknown flag" "$OUTPUT" "--some-flag"
assert_contains "pi receives flag value" "$OUTPUT" "value"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 3: pi-box with no args runs pi with no args ----

echo ""
echo "=== test 3: pi-box with no args runs pi ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box 2>&1)
EXIT_CODE=$?
set -e

assert_exit "no args exits 0" 0 "$EXIT_CODE"
assert_contains "pi called even with no args" "$OUTPUT" "pi-output:"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 4: pi-box with multiple args passes all to pi ----

echo ""
echo "=== test 4: multiple args pass through ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box "explain this code" --verbose 2>&1)
EXIT_CODE=$?
set -e

assert_exit "multiple args exits 0" 0 "$EXIT_CODE"
assert_contains "first arg passes through" "$OUTPUT" "explain this code"
assert_contains "second arg passes through" "$OUTPUT" "--verbose"

trap - EXIT
rm -rf "$TEST_HOME"

summary
