#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Agent settings need merging and backups before Stow replaces existing files.
bash agents/.config/agent-setup/apply.sh --repo "$PWD" --apply --integrations
for package in */; do
  case "$package" in agents/|claude/|herdr/|workmux/|docs/|tests/|scripts/) continue ;; esac
  stow -v "${package%/}"
done
ya pkg install
