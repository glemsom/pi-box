#!/usr/bin/env bash
# setup.sh — configure the pi-box base environment
set -u

# Pre-flight: devbox must be installed
if ! command -v devbox &>/dev/null; then
  echo "Error: devbox is not installed. Please install devbox first: https://www.jetify.com/devbox/docs/installing_devbox/"
  exit 1
fi

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
  # Create directories
  mkdir -p "$(dirname "$GLOBAL_CONFIG")" || { echo "Error: cannot create directory $(dirname "$GLOBAL_CONFIG")"; exit 2; }
  mkdir -p "$HOME/.pi-box/npm" || { echo "Error: cannot create directory $HOME/.pi-box/npm"; exit 2; }

  # Write canonical base box config
  cat > "$GLOBAL_CONFIG" << 'DEVENDOF' || { echo "Error: cannot write $GLOBAL_CONFIG"; exit 3; }
{
  "packages": [
    "nodejs@22"
  ],
  "env": {
    "NPM_CONFIG_PREFIX": "$HOME/.pi-box/npm",
    "PATH": "$HOME/.pi-box/npm/bin:$PATH"
  },
  "shell": {
    "init_hook": [
      "command -v pi || (npm install -g @earendil-works/pi-coding-agent && pi install npm:@dreki-gg/pi-context7)"
    ]
  }
}
DEVENDOF

  echo "pi-box base environment configured successfully"
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
