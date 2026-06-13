# pi-box — isolated, reproducible Pi agent using devbox
#
# Source this file in your .bashrc to enable the pi-box command:
#   source /path/to/pi-box.sh
#
# The function activates the global devbox environment and runs Pi.
# On first invocation, the init_hook installs Pi and extensions automatically.

pi-box() {
  # Project devbox.json detection: when a project-level devbox.json exists,
  # use devbox shell to enter the project environment (which layers on top
  # of the global base box) and run Pi inside it.
  if [[ -f ./devbox.json ]]; then
    if [[ "${1:-}" == "--shell" ]]; then
      devbox shell
      return
    fi
    devbox shell -- pi "$@"
    return
  fi

  # No project devbox.json: activate global environment and run Pi
  eval "$(devbox global shellenv --init-hook)"
  pi "$@"
}
