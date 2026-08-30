#!/usr/bin/env bash
# Lay out a freshly created worktree workspace: nvim on the left, a working
# shell on the right holding focus. Runs on every worktree.created event, so
# an agent's `herdr worktree create` gets the same layout as the keybinding.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
workspace="${HERDR_WORKSPACE_ID:-}"
# Event payloads are wrapped as {"event": ..., "data": {...}}, not the bare
# socket event shape the API schema documents.
path=$(jq -r '.data.worktree.path // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
[ -n "$workspace" ] && [ -n "$path" ] || exit 0

panes=$("$herdr" pane list --workspace "$workspace")
# Only lay out an untouched workspace; never rearrange one already in use.
[ "$(jq '.result.panes | length' <<<"$panes")" -eq 1 ] || exit 0
root=$(jq -r '.result.panes[0].pane_id' <<<"$panes")

"$herdr" pane split --pane "$root" --direction right --cwd "$path" --ratio 0.6 --focus >/dev/null
"$herdr" pane run "$root" nvim
