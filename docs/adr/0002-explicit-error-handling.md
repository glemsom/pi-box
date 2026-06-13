# Explicit error handling over `set -e` and `set -o pipefail`

Shell scripts in pi-box use `set -u` only. `set -e` and `set -o pipefail` are deliberately omitted. Every command whose failure matters gets explicit `|| { ...; exit N; }` handling, and dependencies are checked at the top of each script.

The trade-off: `set -e` makes every unchecked command a hidden exit point — error modes are implicit and hard to reason about locally. Explicit handling makes failure paths visible at the call site, at the cost of more boilerplate. For pi-box's scale (~40-line scripts), the boilerplate is negligible and the clarity wins.
