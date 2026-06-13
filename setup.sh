#!/usr/bin/env bash
# setup.sh — configure the pi-box base environment
set -euo pipefail

# Pre-flight: devbox must be installed
if ! command -v devbox &>/dev/null; then
  echo "Error: devbox is not installed. Please install devbox first: https://www.jetify.com/devbox/docs/installing_devbox/"
  exit 1
fi

GLOBAL_CONFIG="$HOME/.local/share/devbox/global/default/devbox.json"

# Check if already configured (idempotency)
if [[ -f "$GLOBAL_CONFIG" ]]; then
  if grep -q '"nodejs' "$GLOBAL_CONFIG" 2>/dev/null; then
    if [[ "${1:-}" != "--force" ]]; then
      echo "nothing to do"
      exit 0
    fi
  fi
fi

# Create directories
mkdir -p "$(dirname "$GLOBAL_CONFIG")"
mkdir -p "$HOME/.pi-box/npm"

# Write canonical base box config
cat > "$GLOBAL_CONFIG" << 'DEVENDOF'
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
