#!/usr/bin/env bash
# Integration tests for setup.sh
# Tests verify observable CLI behavior — exit codes, stdout/stderr, file existence.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "Error: cannot determine script directory"; exit 1; }
SETUP_SH="$SCRIPT_DIR/../setup.sh"
[[ -f "$SETUP_SH" ]] || { echo "Error: $SETUP_SH not found"; exit 1; }

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

assert_dir_exists() {
  local desc="$1" path="$2"
  if [[ -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (directory not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_valid_json() {
  local desc="$1" path="$2"
  if command -v jq &>/dev/null; then
    if jq empty "$path" 2>/dev/null; then
      echo "  PASS: $desc"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $desc (invalid JSON in $path)"
      FAIL=$((FAIL + 1))
    fi
  elif command -v python3 &>/dev/null; then
    if python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
      echo "  PASS: $desc"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $desc (invalid JSON in $path)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  SKIP: $desc (no JSON validator available)"
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

# Create a temp HOME with mock devbox installed.
# Sets TEST_HOME, HOME, and PATH in the calling scope.
# Caller must set up trap for cleanup using $TEST_HOME.
setup_test_env() {
  TEST_HOME=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 2; }
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/bin" || { echo "FATAL: cannot create $TEST_HOME/bin" >&2; exit 2; }
  cat > "$TEST_HOME/bin/devbox" << 'FAKEDEVBOX' || { echo "FATAL: cannot write fake devbox" >&2; exit 2; }
#!/usr/bin/env bash
true
FAKEDEVBOX
  chmod +x "$TEST_HOME/bin/devbox" || { echo "FATAL: cannot chmod fake devbox" >&2; exit 2; }
  export PATH="$TEST_HOME/bin:/usr/bin:/bin"
  export PI_BOX_SKIP_NIX_CHECK=1
}

# ---- test 1: missing devbox ----

echo ""
echo "=== test 1: missing devbox ==="

TEST_HOME=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
export PATH="/usr/bin:/bin"

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "missing devbox exits non-zero" 1 "$EXIT_CODE"
assert_contains "missing devbox prints error" "$OUTPUT" "devbox"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 2: fresh install creates global config ----

echo ""
echo "=== test 2: fresh install creates global config ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

GLOBAL_CONFIG="$TEST_HOME/.local/share/devbox/global/default/devbox.json"

assert_exit "fresh install exits 0" 0 "$EXIT_CODE"
assert_file_exists "fresh install creates devbox.json" "$GLOBAL_CONFIG"
assert_valid_json "fresh install produces valid JSON" "$GLOBAL_CONFIG"

CONFIG_CONTENT=$(cat "$GLOBAL_CONFIG")
assert_contains "config has nodejs@26" "$CONFIG_CONTENT" 'nodejs@26'
assert_contains "config has NPM_CONFIG_PREFIX" "$CONFIG_CONTENT" 'NPM_CONFIG_PREFIX'
assert_contains "config has PATH env" "$CONFIG_CONTENT" '.pi-box/npm/bin'
assert_contains "config has init_hook" "$CONFIG_CONTENT" 'init_hook'
assert_contains "config has guard command" "$CONFIG_CONTENT" 'command -v pi'
assert_contains "config has npm install" "$CONFIG_CONTENT" 'npm install -g'
assert_contains "config has pi install" "$CONFIG_CONTENT" 'pi install npm:@dreki-gg/pi-context7'

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 3: creates npm prefix directory ----

echo ""
echo "=== test 3: creates npm prefix directory ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

bash "$SETUP_SH" > /dev/null 2>&1

NPM_DIR="$TEST_HOME/.pi-box/npm"
assert_dir_exists "npm prefix directory created" "$NPM_DIR"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 4: idempotent — second run says nothing to do ----

echo ""
echo "=== test 4: idempotent — second run says nothing to do ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

bash "$SETUP_SH" > /dev/null 2>&1

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "second run exits 0" 0 "$EXIT_CODE"
assert_contains "second run prints nothing to do" "$OUTPUT" "nothing to do"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 5: --force overwrites existing config ----

echo ""
echo "=== test 5: --force overwrites existing config ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

GLOBAL_CONFIG="$TEST_HOME/.local/share/devbox/global/default/devbox.json"

bash "$SETUP_SH" > /dev/null 2>&1
echo '{"packages":["python@3"]}' > "$GLOBAL_CONFIG"

OUTPUT=$(bash "$SETUP_SH" --force 2>&1)
EXIT_CODE=$?

assert_exit "--force exits 0" 0 "$EXIT_CODE"
CONFIG_CONTENT=$(cat "$GLOBAL_CONFIG")
assert_contains "--force restores nodejs@26" "$CONFIG_CONTENT" 'nodejs@26'
if echo "$CONFIG_CONTENT" | grep -q 'python'; then
  echo "  FAIL: --force removes python (config still has python)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: --force removes python"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 6: does NOT run npm install ----

echo ""
echo "=== test 6: does NOT run npm install ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Overlay a fake npm that records calls
cat > "$TEST_HOME/bin/npm" << 'FAKENPM' || { echo "FATAL: cannot write fake npm" >&2; exit 2; }
#!/usr/bin/env bash
echo "npm was called with args: $*" > "$HOME/npm-called.txt"
exit 1
FAKENPM
chmod +x "$TEST_HOME/bin/npm" || { echo "FATAL: cannot chmod fake npm" >&2; exit 2; }

bash "$SETUP_SH" > /dev/null 2>&1

NPM_CALLED="$TEST_HOME/npm-called.txt"
if [[ -f "$NPM_CALLED" ]]; then
  echo "  FAIL: setup.sh ran npm install (should not)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: setup.sh does not run npm install"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 7: setup.sh detects missing pi-box function and prints instructions ----

echo ""
echo "=== test 7: setup.sh detects missing pi-box function ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Ensure pi-box function is NOT defined
unset -f pi-box 2>/dev/null || true

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "setup without pi-box function exits 0" 0 "$EXIT_CODE"
assert_contains "setup mentions adding pi-box to .bashrc" "$OUTPUT" ".bashrc"
assert_contains "setup mentions pi-box.sh" "$OUTPUT" "pi-box.sh"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 8: idempotent run still reminds about missing pi-box function ----

echo ""
echo "=== test 8: idempotent run reminds about missing pi-box ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# First run creates config
bash "$SETUP_SH" > /dev/null 2>&1

# pi-box function is NOT defined
unset -f pi-box 2>/dev/null || true

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "idempotent run exits 0" 0 "$EXIT_CODE"
assert_contains "prints nothing to do" "$OUTPUT" "nothing to do"
assert_contains "still reminds about .bashrc" "$OUTPUT" ".bashrc"
assert_contains "still mentions pi-box.sh" "$OUTPUT" "pi-box.sh"

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 9: setup.sh is silent about pi-box when function already exists ----

echo ""
echo "=== test 9: setup.sh silent when pi-box function present ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Define a dummy pi-box function in the test's shell
pi-box() { true; }
export -f pi-box

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "setup with pi-box function exits 0" 0 "$EXIT_CODE"
# Should NOT contain .bashrc instruction since function exists
if echo "$OUTPUT" | grep -qF -- ".bashrc"; then
  echo "  FAIL: setup printed .bashrc instruction even though pi-box function exists"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: setup does not print .bashrc instruction when function exists"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 10: setup exits early when /nix missing on Linux ----

echo ""
echo "=== test 10: setup exits early when /nix missing ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Remove the skip guard so the pre-flight actually runs
unset PI_BOX_SKIP_NIX_CHECK

OUTPUT=$(bash "$SETUP_SH" 2>&1)
EXIT_CODE=$?

assert_exit "missing /nix exits 4" 4 "$EXIT_CODE"
assert_contains "error mentions /nix" "$OUTPUT" "/nix"
assert_contains "error gives sudo mkdir fix" "$OUTPUT" "sudo mkdir"
assert_contains "error gives sudo chown fix" "$OUTPUT" "sudo chown"
assert_contains "error says re-run" "$OUTPUT" "re-run"

# Config should NOT have been written (pre-flight blocked before config write)
GLOBAL_CONFIG="$TEST_HOME/.local/share/devbox/global/default/devbox.json"
if [[ -f "$GLOBAL_CONFIG" ]]; then
  echo "  FAIL: devbox.json was written (should have been blocked by pre-flight)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: devbox.json not written (pre-flight blocked it)"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 11: setup.sh source includes "not writable" error for the /nix writability check ----

echo ""
echo "=== test 11: setup.sh has not-writable error message ==="

# Since creating a non-writable /nix requires root, verify the source code
# contains the expected diagnostic for the "exists but not writable" case.
SETUP_SRC=$(cat "$SETUP_SH")
if echo "$SETUP_SRC" | grep -qF 'exists but is not writable by your user'; then
  echo "  PASS: setup.sh contains not-writable error message"
  PASS=$((PASS + 1))
else
  echo "  FAIL: setup.sh missing not-writable error message"
  FAIL=$((FAIL + 1))
fi
if echo "$SETUP_SRC" | grep -qF 'sudo chown \$USER /nix'; then
  echo "  PASS: setup.sh contains sudo chown fix for not-writable case"
  PASS=$((PASS + 1))
else
  echo "  FAIL: setup.sh missing sudo chown fix"
  FAIL=$((FAIL + 1))
fi

summary
