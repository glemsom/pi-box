#!/usr/bin/env bash
# setup.sh — configure the pi-box base environment
set -u

# Pre-flight: devbox must be installed
if ! command -v devbox &>/dev/null; then
  echo "Error: devbox is not installed. Please install devbox first: https://www.jetify.com/devbox/docs/installing_devbox/"
  exit 1
fi

# Extract package definitions from pi-box.sh (single source of truth).
# Uses grep+eval to import only the variable assignments, not the functions.
_PI_BOX_SH="$(dirname "$(readlink -f "$0")")/pi-box.sh"
eval "$(grep '^PI_BOX_PI_PKG=\|^PI_BOX_CTX7_PKG=' "$_PI_BOX_SH")" || { echo "Error: cannot read package definitions from pi-box.sh"; exit 5; }

GLOBAL_CONFIG="$HOME/.local/share/devbox/global/default/devbox.json"

ALREADY_CONFIGURED=false
# Check if already configured (idempotency)
if [[ -f "$GLOBAL_CONFIG" ]]; then
  if grep -q '"nodejs' "$GLOBAL_CONFIG" 2>/dev/null; then
    if [[ "${1:-}" != "--force" ]]; then
      ALREADY_CONFIGURED=true
    fi
  fi
fi

if $ALREADY_CONFIGURED; then
  echo "nothing to do"
else
  # Pre-flight: check nix store exists on Linux before configuring.
  # Set PI_BOX_SKIP_NIX_CHECK=1 to bypass (used by tests).
  if [[ "$(uname -s)" == "Linux" ]] && [[ "${PI_BOX_SKIP_NIX_CHECK:-}" != "1" ]]; then
    if ! test -d /nix 2>/dev/null; then
      echo "Error: /nix directory not found. Devbox requires nix, which needs /nix to store packages." >&2
      echo "  Fix:  sudo mkdir -p /nix && sudo chown \$USER /nix" >&2
      echo "  Then re-run setup.sh." >&2
      exit 4
    elif ! test -w /nix 2>/dev/null; then
      echo "Error: /nix exists but is not writable by your user. Devbox requires nix, which needs write access to /nix to store packages." >&2
      echo "  Fix:  sudo chown \$USER /nix" >&2
      echo "  Then re-run setup.sh." >&2
      exit 4
    fi
  fi

  # Create directories
  mkdir -p "$(dirname "$GLOBAL_CONFIG")" || { echo "Error: cannot create directory $(dirname "$GLOBAL_CONFIG")"; exit 2; }
  mkdir -p "$HOME/.pi-box/npm" || { echo "Error: cannot create directory $HOME/.pi-box/npm"; exit 2; }

  # Write canonical base box config
  cat > "$GLOBAL_CONFIG" << DEVENDOF || { echo "Error: cannot write $GLOBAL_CONFIG"; exit 3; }
{
  "packages": [
    "nodejs@26"
  ],
  "env": {
    "NPM_CONFIG_PREFIX": "\$HOME/.pi-box/npm",
    "PATH": "\$HOME/.pi-box/npm/bin:\$PATH"
  },
  "shell": {
    "init_hook": [
      "command -v pi || (npm install -g ${PI_BOX_PI_PKG} && pi install npm:${PI_BOX_CTX7_PKG})"
    ]
  }
}
DEVENDOF

  echo "pi-box base environment configured successfully"

  # Trigger initial environment build so .hooks.sh is generated.
  # Capture stderr and exit code for diagnostics — nix permission errors are common.
  DEVERROR=$(devbox global shellenv --recompute 2>&1 >/dev/null); DEVBEXIT=$?
  if [[ ${DEVBEXIT:-0} -ne 0 || -n "${DEVERROR:-}" ]]; then
    if echo "${DEVERROR:-}" | grep -qiF -e "permission denied" -e "/nix/store" -e "creating directory"; then
      echo "Warning: devbox cannot access /nix/store (permission denied)." >&2
      echo "  For nix installation: https://nixos.org/download" >&2
      echo "  For devbox setup: https://www.jetify.com/devbox/docs/installing_devbox/" >&2
    else
      echo "Warning: devbox global shellenv --recompute reported errors. First pi-box run may trigger a build." >&2
    fi
  fi
fi

# Check if pi-box function is available in the current shell
if ! declare -F pi-box &>/dev/null; then
  echo ""
  echo "To enable the pi-box command, add the following to your ~/.bashrc:"
  echo ""
  echo "  source $(dirname "$(readlink -f "$0")")/pi-box.sh"
  echo ""
  echo "Then restart your shell or run: source ~/.bashrc"
fi
