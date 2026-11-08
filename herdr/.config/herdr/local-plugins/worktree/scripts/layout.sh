#!/usr/bin/env bash
# Starts the session new-worktree.sh left waiting for a freshly created worktree as its space's
# one pane, so the space is that session alone. Runs on every worktree.created event; one with
# no session waiting (alt-enter, an agent's `herdr worktree create`) keeps its shell.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
waiting="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/worktree}/waiting"
workspace="${HERDR_WORKSPACE_ID:-}"
# Event payloads are wrapped as {"event": ..., "data": {...}}, not the bare
# socket event shape the API schema documents.
path=$(jq -r '.data.worktree.path // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
session="$waiting/${path//\//_}"
[ -n "$workspace" ] && [ -n "$path" ] && [ -f "$session" ] || exit 0

panes=$("$herdr" pane list --workspace "$workspace")
# Only into an untouched workspace; never into one already in use.
[ "$(jq '.result.panes | length' <<<"$panes")" -eq 1 ] || exit 0
"$herdr" pane run "$(jq -r '.result.panes[0].pane_id' <<<"$panes")" "$(cat "$session")"
rm -f "$session"
