# pi-box — isolated, reproducible Pi agent using devbox
#
# Source this file in your .bashrc to enable the pi-box command:
#   source /path/to/pi-box.sh
#
# The function activates the global devbox environment and runs Pi.
# On first invocation, the init_hook installs Pi and extensions automatically.
set -u

pi-box() {
  # --update flag: refresh Pi and extensions to latest versions.
  # Works in both project and no-project contexts.
  if [[ "${1:-}" == "--update" ]]; then
    eval "$(devbox global shellenv --init-hook)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
    npm update -g @earendil-works/pi-coding-agent || { echo "Error: npm update failed" >&2; return 2; }
    pi install npm:@dreki-gg/pi-context7 || { echo "Error: pi install context7 failed" >&2; return 3; }
    return
  fi

  # Project devbox.json detection: when a project-level devbox.json exists,
  # use devbox shell to enter the project environment (which layers on top
  # of the global base box) and run Pi inside it.
  if [[ -f ./devbox.json ]]; then
    if [[ "${1:-}" == "--shell" ]]; then
      devbox shell || { echo "Error: devbox shell failed" >&2; return 4; }
      return
    fi
    devbox shell -- pi "$@"
    return
  fi

  # --shell flag (no-project): activate global environment, drop into interactive shell.
  if [[ "${1:-}" == "--shell" ]]; then
    eval "$(devbox global shellenv --init-hook)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
    exec bash || { echo "Error: exec bash failed" >&2; return 5; }
  fi

  # No project devbox.json: activate global environment and run Pi
  eval "$(devbox global shellenv --init-hook)" || { echo "Error: devbox global shellenv failed" >&2; return 1; }
  pi "$@"
}
