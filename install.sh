#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Agent settings need merging and backups before Stow replaces existing files.
bash agents/.config/agent-setup/apply.sh --repo "$PWD" --apply --integrations
for package in */; do
  case "$package" in agents/|claude/|herdr/|herdr-app/|workmux/|docs/|tests/|scripts/) continue ;; esac
  stow -v "${package%/}"
done
# herdr-app draws no symlinked icon and doesn't reload symlinked mods, so it gets copies.
bash herdr-app/sync.sh
ya pack -i
