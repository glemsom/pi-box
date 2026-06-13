# pi-box

Isolated, reproducible Pi agent environment using devbox. Makes Pi self-contained so the only host dependency is devbox itself.

## Language

**pi-box**:
The project and the user-facing command that enters the Pi dev environment.
_Avoid_: pi-in-a-box, pibox

**Base box**:
The machine-wide global devbox configuration (~/.local/share/devbox/global/default/devbox.json) that provides `nodejs`, Pi, and default extensions. Managed by `setup.sh` and shared across all projects.
_Avoid_: global config, default box

**Project box**:
A per-repository `devbox.json` that optionally extends the base box with additional project-specific packages. When the `pi-box` command is run in a directory with a `devbox.json`, it layers on top of the base box.
_Avoid_: local config, repo devbox

**setup.sh**:
The idempotent setup script shipped in the pi-box repo. Edits the global devbox config to declare the base box packages, env vars, and init hooks. Does not install packages — deferred to first run.
_Avoid_: install.sh, bootstrap

**_die**:
Shell function that prints an error message to stderr (prefixed with `Error: `) and returns exit code 1. Used by all failure paths in `pi-box.sh` to ensure consistent, human-readable error output.
_Avoid_: _fail, _fatal, _error_handler

**Pi**:
The `pi` CLI binary from the `@earendil-works/pi-coding-agent` npm package. Runs inside the devbox environment, not on the host.
_Avoid_: Pi agent, coding agent
