#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Agent settings need merging and backups before Stow replaces existing files.
bash agents/.config/agent-setup/apply.sh --repo "$PWD" --apply --integrations
# Without it Stow links the whole folder, and herdr-app then writes its state into the repo.
mkdir -p ~/.config/herdr-app/{mods,layouts,themes}
# herdr-app keeps the shown layout only in its own state, so a new Mac starts on ours.
if [ ! -e ~/.config/herdr-app/shared.json ]; then
  echo '{"layout":"tree"}' > ~/.config/herdr-app/shared.json
fi
for package in */; do
  case "$package" in agents/|claude/|herdr/|workmux/|docs/|tests/|scripts/) continue ;; esac
  stow -v "${package%/}"
done
# atuin's daemon starts with the first rebuild, before Stow, and writes a default
# ~/.atuin/config.toml that atuin then reads instead of ours.
if [ -e ~/.atuin/config.toml ]; then
  mv ~/.atuin/config.toml ~/.atuin/config.toml.default
  launchctl kickstart -k "gui/$(id -u)/org.nixos.atuin-daemon"
fi
ya pkg install
# pnpm, node and npm are Vite+'s shims; its ~/.zshenv puts them on every zsh's PATH.
vp env setup
vp env on
