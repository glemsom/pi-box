#!/usr/bin/env bash
# Integration tests for pi-box BASH function
# Tests verify observable CLI behavior through the public function interface.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "Error: cannot determine script directory"; exit 1; }
PI_BOX_SH="$SCRIPT_DIR/../pi-box.sh"
[[ -f "$PI_BOX_SH" ]] || { echo "Error: $PI_BOX_SH not found"; exit 1; }

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
  TEST_HOME=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 2; }
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/bin" || { echo "FATAL: cannot create $TEST_HOME/bin" >&2; exit 2; }

  # Fake devbox: records invocations
  cat > "$TEST_HOME/bin/devbox" << 'FAKEDEVBOX' || { echo "FATAL: cannot write fake devbox" >&2; exit 2; }
#!/usr/bin/env bash
echo "devbox called with: $*" >> "$HOME/devbox-calls.log"
if [[ "$*" == *"global shellenv --init-hook"* ]]; then
  # Emit shellenv that adds our fake bin to PATH
  echo "export PATH=\"$HOME/bin:\$PATH\""
fi
true
FAKEDEVBOX
  chmod +x "$TEST_HOME/bin/devbox" || { echo "FATAL: cannot chmod fake devbox" >&2; exit 2; }

  # Fake pi: records invocations and arguments
  cat > "$TEST_HOME/bin/pi" << 'FAKEPI' || { echo "FATAL: cannot write fake pi" >&2; exit 2; }
#!/usr/bin/env bash
echo "pi called with: $*" >> "$HOME/pi-calls.log"
echo "pi-output: $*"
true
FAKEPI
  chmod +x "$TEST_HOME/bin/pi" || { echo "FATAL: cannot chmod fake pi" >&2; exit 2; }

  export PATH="$TEST_HOME/bin:/usr/bin:/bin"
  export PI_BOX_SKIP_NIX_CHECK=1
}

# ---- test 1: pi-box "help" activates devbox and runs pi with "help" (tracer bullet) ----

echo ""
echo "=== test 1: pi-box \"help\" activates devbox and runs pi ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Source the function definition
source "$PI_BOX_SH"

OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?

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

OUTPUT=$(pi-box --some-flag value 2>&1)
EXIT_CODE=$?

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

OUTPUT=$(pi-box 2>&1)
EXIT_CODE=$?

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

OUTPUT=$(pi-box "explain this code" --verbose 2>&1)
EXIT_CODE=$?

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
cd "$PROJECT_DIR" || { echo "FATAL: cd to project dir failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?

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
cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?

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

cd "$PROJECT_DIR" || { echo "FATAL: cd to project dir failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box --shell 2>&1)
EXIT_CODE=$?

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

cd "$PROJECT_DIR" || { echo "FATAL: cd to project dir failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box "explain this code" --verbose 2>&1)
EXIT_CODE=$?

if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox shell with full args" "$DEVCALLS" "shell -- pi explain this code --verbose"
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 9: pi-box --shell in no-project context opens interactive shell ----

echo ""
echo "=== test 9: --shell in no-project context activates shellenv and blocks pi ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

cd "$TEST_HOME"
source "$PI_BOX_SH"

# Run in a subshell since --shell exec's into an interactive shell
# Pass PI_BOX_SH into the subshell context
OUTPUT=$(PI_BOX_SH="$PI_BOX_SH" bash -c 'source "$PI_BOX_SH" 2>/dev/null; pi-box --shell 2>&1' 2>&1)
EXIT_CODE=$?

# --shell exits 0 (the exec'd bash exits clean when stdin is not a tty)
assert_exit "--shell exits 0" 0 "$EXIT_CODE"

# devbox global shellenv should be called
if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  DEVCALLS=$(cat "$TEST_HOME/devbox-calls.log")
  assert_contains "devbox global shellenv called for --shell" "$DEVCALLS" "global shellenv --init-hook"
else
  echo "  FAIL: devbox was never called"
  FAIL=$((FAIL + 1))
fi

# pi should NOT have been called (--shell is intercepted, not passed through)
if [[ -f "$TEST_HOME/pi-calls.log" ]]; then
  echo "  FAIL: pi was called (should not run for --shell)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: pi not called for --shell"
  PASS=$((PASS + 1))
fi

# --shell should NOT appear in pi-calls (regression check)
if echo "$OUTPUT" | grep -qF -- "--shell"; then
  echo "  FAIL: --shell leaked to output"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: --shell not in output"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 10: pi-box --update refreshes packages ----

echo ""
echo "=== test 10: --update refreshes packages ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Create fake npm that records calls
cat > "$TEST_HOME/bin/npm" << 'FAKENPM'
#!/usr/bin/env bash
echo "npm called with: $*" >> "$HOME/npm-calls.log"
true
FAKENPM
chmod +x "$TEST_HOME/bin/npm" || { echo "FATAL: cannot chmod fake npm" >&2; exit 2; }

cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box --update 2>&1)
EXIT_CODE=$?

assert_exit "--update exits 0" 0 "$EXIT_CODE"

# npm should have been called to update pi
if [[ -f "$TEST_HOME/npm-calls.log" ]]; then
  NPMCALLS=$(cat "$TEST_HOME/npm-calls.log")
  assert_contains "npm update called for pi" "$NPMCALLS" "update -g @earendil-works/pi-coding-agent"
else
  echo "  FAIL: npm was never called"
  FAIL=$((FAIL + 1))
fi

# pi should have been called to install context7
if [[ -f "$TEST_HOME/pi-calls.log" ]]; then
  PICALLS=$(cat "$TEST_HOME/pi-calls.log")
  assert_contains "pi install context7 called" "$PICALLS" "install npm:@dreki-gg/pi-context7"
else
  echo "  FAIL: pi install was never called"
  FAIL=$((FAIL + 1))
fi

# pi should NOT have received --update as an argument
if echo "$OUTPUT" | grep -qF -- "--update"; then
  echo "  FAIL: --update leaked to output"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: --update not passed through"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 11: --update works in project context too ----

echo ""
echo "=== test 11: --update works in project context ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Create fake npm that records calls
cat > "$TEST_HOME/bin/npm" << 'FAKENPM' || { echo "FATAL: cannot write fake npm" >&2; exit 2; }
#!/usr/bin/env bash
echo "npm called with: $*" >> "$HOME/npm-calls.log"
true
FAKENPM
chmod +x "$TEST_HOME/bin/npm" || { echo "FATAL: cannot chmod fake npm" >&2; exit 2; }

PROJECT_DIR="$TEST_HOME/project"
mkdir -p "$PROJECT_DIR" || { echo "FATAL: cannot create project dir" >&2; exit 2; }
cat > "$PROJECT_DIR/devbox.json" << 'DEVJSON' || { echo "FATAL: cannot write project devbox.json" >&2; exit 2; }
{
  "packages": ["python@3"]
}
DEVJSON

cd "$PROJECT_DIR" || { echo "FATAL: cd to project dir failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box --update 2>&1)
EXIT_CODE=$?

assert_exit "--update in project exits 0" 0 "$EXIT_CODE"

# npm update should still run (global update)
if [[ -f "$TEST_HOME/npm-calls.log" ]]; then
  NPMCALLS=$(cat "$TEST_HOME/npm-calls.log")
  assert_contains "npm update in project context" "$NPMCALLS" "update -g @earendil-works/pi-coding-agent"
else
  echo "  FAIL: npm was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 12: built-in flags don't block unknown flags (regression) ----

echo ""
echo "=== test 12: unknown flags still pass through (regression) ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box --custom-flag "some value" 2>&1)
EXIT_CODE=$?

assert_exit "unknown flag exits 0" 0 "$EXIT_CODE"

if [[ -f "$TEST_HOME/pi-calls.log" ]]; then
  PICALLS=$(cat "$TEST_HOME/pi-calls.log")
  assert_contains "unknown flag passes through" "$PICALLS" "--custom-flag"
else
  echo "  FAIL: pi was never called"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 13: devbox nix failure gives diagnostic error (not just --update) ----

echo ""
echo "=== test 13: devbox nix failure gives diagnostic error ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Override fake pi — pi must NOT be on PATH for this test
rm -f "$TEST_HOME/bin/pi"

# Override fake devbox to simulate nix permission failure:
# - prints nix + devbox errors to stderr
# - outputs a shellenv that does NOT include pi in PATH
# - exits 0 (so eval succeeds but pi isn't available)
cat > "$TEST_HOME/bin/devbox" << 'FAKEDEVBOX'
#!/usr/bin/env bash
echo "devbox called with: $*" >> "$HOME/devbox-calls.log"
if [[ "$*" == *"global shellenv --init-hook"* ]]; then
  echo "Info: Ensuring packages are installed." >&2
  echo "Error: nix: command error: nix --extra-experimental-features ca-derivations --option experimental-features 'nix-command flakes fetch-closure' path-info --offline --json /nix/store/ac9bklddx1klg92hj7r08xmpky1nwag2-nodejs-26.0.0: creating directory \"/nix/store\": Permission denied: exit code 1" >&2
  echo "Error: There was an internal error. Run with DEVBOX_DEBUG=1 for a detailed error message, and consider reporting it at https://github.com/jetify-com/devbox/issues" >&2
  # Emit shellenv WITHOUT pi in PATH — simulates devbox exiting 0 but broken env
  echo "export PATH=\"/usr/bin:/bin\""
fi
true
FAKEDEVBOX
chmod +x "$TEST_HOME/bin/devbox"

cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?

assert_exit "nix failure exits non-zero" 1 "$EXIT_CODE"
# Error message must NOT suggest --update (won't fix nix permissions)
if echo "$OUTPUT" | grep -qF -- "--update"; then
  echo "  FAIL: error message suggests --update (unhelpful for nix permission issues)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: error message does not suggest --update"
  PASS=$((PASS + 1))
fi
# Error message should mention nix or devbox or permission as possible causes
if echo "$OUTPUT" | grep -qFi -e "nix" -e "devbox" -e "permission" -e "check the output above" -e "diagnos"; then
  echo "  PASS: error message contains diagnostic hint (nix/devbox/permission)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: error message lacks diagnostic hint"
  echo "  output was: $OUTPUT"
  FAIL=$((FAIL + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 14: pre-flight nix check fires when /nix missing on Linux ----

echo ""
echo "=== test 14: pre-flight nix check fires when /nix missing ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Remove the skip guard so the pre-flight actually runs
unset PI_BOX_SKIP_NIX_CHECK

cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

OUTPUT=$(pi-box "help" 2>&1)
EXIT_CODE=$?

assert_exit "missing /nix exits 1" 1 "$EXIT_CODE"
assert_contains "error mentions /nix" "$OUTPUT" "/nix"
assert_contains "error gives sudo mkdir fix" "$OUTPUT" "sudo mkdir"
assert_contains "error gives sudo chown fix" "$OUTPUT" "sudo chown"

# devbox should NOT have been called (pre-flight caught it early)
if [[ -f "$TEST_HOME/devbox-calls.log" ]]; then
  echo "  FAIL: devbox was called (should have been blocked by pre-flight)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: devbox not called (pre-flight blocked it)"
  PASS=$((PASS + 1))
fi

trap - EXIT
rm -rf "$TEST_HOME"

# ---- test 15: _nix_store_ok detects non-writable /nix (function unit test) ----

echo ""
echo "=== test 15: _nix_store_ok detects non-writable nix dir ==="

setup_test_env
trap 'rm -rf "$TEST_HOME"' EXIT

# Remove skip guard so the check actually runs
unset PI_BOX_SKIP_NIX_CHECK

cd "$TEST_HOME" || { echo "FATAL: cd to test home failed" >&2; exit 2; }
source "$PI_BOX_SH"

# Create a non-writable directory to test the check
NONWRITABLE_DIR="$TEST_HOME/nonwritable-nix"
mkdir -p "$NONWRITABLE_DIR" || { echo "FATAL: cannot create test dir" >&2; exit 2; }
chmod 555 "$NONWRITABLE_DIR" || { echo "FATAL: cannot chmod test dir" >&2; exit 2; }

OUTPUT=$(_nix_store_ok "$NONWRITABLE_DIR" 2>&1)
EXIT_CODE=$?

assert_exit "non-writable nix dir exits non-zero" 1 "$EXIT_CODE"
assert_contains "error mentions dir path" "$OUTPUT" "$NONWRITABLE_DIR"
assert_contains "error says not writable" "$OUTPUT" "not writable"
assert_contains "error gives sudo chown fix" "$OUTPUT" "sudo chown"

# Cleanup: restore writability so rm -rf works
chmod 755 "$NONWRITABLE_DIR" 2>/dev/null || true

trap - EXIT
rm -rf "$TEST_HOME"

summary
