---
name: peon
description: Manage Peon sound packs, mute and volume for agents running in herdr. Use when the user asks to adjust agent sounds or notification preferences.
---

Use the installed `peon` CLI. Read `peon help` before changing settings.

- Mute/unmute: `peon pause` / `peon resume`; `peon toggle` switches the current state.
- Inspect settings: `peon status`.
- Volume: `peon volume` to read, `peon volume 0.5` to set.
- Packs: inspect `peon packs list` and the installed CLI's pack-selection commands.

Herdr's local `peon` plugin is the only event source. Do not install Claude or Codex notification adapters. Native herdr agent integrations are still needed for session identity and restoration.

Persistent preferences are in the dotfiles `agents/.config/agent-setup/peon.json` fragment. Runtime pack, rotation and mute choices remain managed by peon. Do not turn terminal-title writes or native agent hooks back on while adjusting sounds.
