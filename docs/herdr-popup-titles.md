# Herdr popup titles

Local patch for Herdr 0.9.0: `nix/.config/nix/patches/herdr-popup-title.patch`.
Custom popup commands use their existing `description` as the border title.
Missing or whitespace-only descriptions retain the upstream `popup` label.
Other command types and plugin panes are unaffected.

The bindings in `herdr/.config/herdr/config.toml` use `Lazygit` for prefix+g
and `GitHub Dashboard` for prefix+h. The patch assigns the terminal's existing
manual label after a successful popup launch; it adds no protocol fields.

Build together with the existing footer patch and run both sets of tests:

```sh
nix build --impure --file nix/.config/nix/footer-preview.nix \
  --arg check true --out-link /tmp/herdr-popup-title-build
```

This produces a preview binary at `/tmp/herdr-popup-title-build/bin/herdr`.
The system package now uses the same patches after a Nix switch; reloading
configuration alone cannot activate a Rust patch in an already running server.

Remove this patch when upstream supports titles for custom popup commands.
If upstream introduces a separate title field, migrate the two bindings first.
