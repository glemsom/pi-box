# Custom npm prefix for Pi and extensions

Devbox's Nix store is immutable, so `npm install --global` fails inside a devbox shell. The recommended workaround (`nodePackages.*` in devbox.json) requires packages to exist in nixpkgs. Pi (`@earendil-works/pi-coding-agent`) and its extensions (`@dreki-gg/pi-context7`) are npm packages not packaged in nixpkgs.

We set `NPM_CONFIG_PREFIX=$HOME/.pi-box/npm` as an env var in the global devbox config, and extend `PATH` to include `$HOME/.pi-box/npm/bin`. This lets `npm install -g` work inside devbox by pointing at a writable prefix outside the Nix store.

Considered: nixifying Pi packages (high maintenance burden); running pi via `npx` (no caching, no version pinning, slower cold start); installing to a project-local `node_modules` (per-project duplication, no global availability).
