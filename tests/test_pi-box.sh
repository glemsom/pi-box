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

# ---- test 5: pi-box in directory with devbox.json uses devbox shell (project layering) ----

echo ""
echo "=== test 5: project devbox.json uses devbox shell ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Create a project directory with a devbox.json
PROJECT_DIR="$TEST_HOME/project"
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/devbox.json" << 'DEVJSON'
{
  "packages": ["python@3"]
}
DEVJSON

# Run pi-box from the project directory
cd "$PROJECT_DIR"
source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?
set -e

assert_exit "project pi-box help exits 0" 0 "$EXIT_CODE"

# Devbox should have been called with 'shell', not 'global shellenv'
if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox shell called for project" "$DEVCALLS" "shell -- pi help"
  if echo "$DEVCALLS" | grep -q "global shellenv"; then
    echo "  FAIL: devbox global shellenv called in project context (should use shell)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: devbox global shellenv NOT called in project context"
    PASS=$((PASS + 1))
  fi
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

cd "$TEST_HOME"
trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 6: pi-box in directory without devbox.json still uses global (regression) ----

echo ""
echo "=== test 6: no devbox.json still uses global shellenv ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# No devbox.json in CWD
cd "$TEST_HOME"
source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?
set -e

assert_exit "no-project pi-box help exits 0" 0 "$EXIT_CODE"
assert_contains "pi receives help argument" "$OUTPUT" "pi-output: help"

if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox global shellenv called" "$DEVCALLS" "global shellenv --init-hook"
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 7: pi-box --shell in project directory opens interactive devbox shell ----

echo ""
echo "=== test 7: --shell in project directory opens interactive shell ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

PROJECT_DIR="$TEST_HOME/project"
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/devbox.json" << 'DEVJSON'
{
  "packages": ["python@3"]
}
DEVJSON

cd "$PROJECT_DIR"
source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box --shell 2>&1)
EXIT_CODE=$?
set -e

# --shell with project devbox.json should run 'devbox shell' (no pi)
if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  # Should call 'devbox shell' without pi
  assert_contains "devbox shell called" "$DEVCALLS" "shell"
  if echo "$DEVCALLS" | grep -qF "shell -- pi"; then
    echo "  FAIL: --shell in project should run devbox shell not devbox shell -- pi"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: --shell does not invoke pi"
    PASS=$((PASS + 1))
  fi
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 8: arguments pass through in project context ----

echo ""
echo "=== test 8: arguments pass through in project context ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

PROJECT_DIR="$TEST_HOME/project"
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/devbox.json" << 'DEVJSON'
{
  "packages": ["go@1.21"]
}
DEVJSON

cd "$PROJECT_DIR"
source "$PI_BOX_SH"

set +e
OUTPUT=$(pi-box "explain this code" --verbose 2>&1)
EXIT_CODE=$?
set -e

if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox shell with full args" "$DEVCALLS" "shell -- pi explain this code --verbose"
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

summary
