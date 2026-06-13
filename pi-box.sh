# pi-box — isolated, reproducible Pi agent using devbox
#
# Source this file in your .bashrc to enable the pi-box command:
#   source /path/to/pi-box.sh
#
# The function activates the global devbox environment and runs Pi.
# On first invocation, the init_hook installs Pi and extensions automatically.
# Pre-flight: verify nix store is accessible on Linux.
# Devbox requires nix, which needs /nix to store packages.
# Set PI_BOX_SKIP_NIX_CHECK=1 to bypass (used by tests).
_nix_store_ok() {
  local nix_dir="${1:-/nix}"
  [[ "${PI_BOX_SKIP_NIX_CHECK:-}" == "1" ]] && return 0
  [[ "$(uname -s)" != "Linux" ]] && return 0
  if ! test -d "$nix_dir" 2>/dev/null; then
    echo "Error: $nix_dir directory not found. Devbox requires nix, which needs $nix_dir to store packages." >&2
    echo "  Fix:  sudo mkdir -p $nix_dir && sudo chown \$USER $nix_dir" >&2
    echo "  Then re-run your command." >&2
    return 1
  elif ! test -w "$nix_dir" 2>/dev/null; then
    echo "Error: $nix_dir exists but is not writable by your user. Devbox requires nix, which needs write access to $nix_dir to store packages." >&2
    echo "  Fix:  sudo chown \$USER $nix_dir" >&2
    echo "  Then re-run your command." >&2
    return 1
  fi
  return 0
}

pi-box() {
  # --update flag: refresh Pi and extensions to latest versions.
  # Works in both project and no-project contexts.
  if [[ "${1:-}" == "--update" ]]; then
    _nix_store_ok || return 7
    eval "$(devbox global shellenv --init-hook --recompute)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
    command -v pi &>/dev/null || { echo "Error: pi not found after shellenv. If devbox reported errors above (nix permission, network, etc.), those must be fixed first. For nix issues: https://nixos.org/download. For devbox setup: https://www.jetify.com/devbox/docs/installing_devbox/" >&2; return 6; }
    npm update -g @earendil-works/pi-coding-agent || { echo "Error: npm update failed" >&2; return 2; }
    pi install npm:@dreki-gg/pi-context7 || { echo "Error: pi install context7 failed" >&2; return 3; }
    return
  fi

  # Project devbox.json detection: when a project-level devbox.json exists,
  # use devbox shell to enter the project environment (which layers on top
  # of the global base box) and run Pi inside it.
  if [[ -f ./devbox.json ]]; then
    _nix_store_ok || return 7
    if [[ "${1:-}" == "--shell" ]]; then
      devbox shell || { echo "Error: devbox shell failed" >&2; return 4; }
      return
    fi
    devbox shell -- pi "$@"
    return
  fi

  # --shell flag (no-project): activate global environment, drop into interactive shell.
  if [[ "${1:-}" == "--shell" ]]; then
    _nix_store_ok || return 7
    eval "$(devbox global shellenv --init-hook --recompute)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
    exec bash || { echo "Error: exec bash failed" >&2; return 5; }
  fi

  # No project devbox.json: activate global environment and run Pi
  _nix_store_ok || return 7
  eval "$(devbox global shellenv --init-hook --recompute)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
  command -v pi &>/dev/null || { echo "Error: pi not found after shellenv. If devbox reported errors above (nix permission, network, etc.), those must be fixed first. For nix issues: https://nixos.org/download. For devbox setup: https://www.jetify.com/devbox/docs/installing_devbox/" >&2; return 6; }
  pi "$@"
}
