#!/usr/bin/env bash
# Install this package into ~/.config/herdr-app as copies, not Stow links: the app draws no
# icon file that is a symlink and doesn't hot-reload a symlinked mod folder. The repo stays the
# source; run `--pull` after changing shortcuts in the app's Settings (it rewrites keys.json) or
# editing a mod in place, to bring those changes back here.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo="$here/.config/herdr-app/"
live="$HOME/.config/herdr-app/"
# The app writes these into every mod folder on each run.
generated=(--exclude gpui-kit.d.ts --exclude jsconfig.json)

if [ "${1:-}" = "--pull" ]; then
  # Only the files the repo keeps: the app's own state (data/, telemetry/, shipped mods) stays put.
  git -C "$repo" ls-files | rsync -ai --files-from=- "$live" "$repo"
  echo "pulled  $live -> $repo"
else
  mkdir -p "$live"
  rsync -ai "${generated[@]}" "$repo" "$live"
  echo "pushed  $repo -> $live"
fi
