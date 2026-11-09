#!/usr/bin/env bash
# Readies a freshly created worktree's space, on every worktree.created event: its one pane runs
# the repo's setup (paseo.json's worktree.setup, as Paseo runs it), then the session
# new-worktree.sh left waiting. With neither (alt-enter, an agent's `herdr worktree create`
# in a repo without one) the pane keeps its bare shell. A failed setup still starts the session;
# its output stays in the pane's scrollback.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
waiting="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/worktree}/waiting"
workspace="${HERDR_WORKSPACE_ID:-}"
# Event payloads are wrapped as {"event": ..., "data": {...}}, not the bare
# socket event shape the API schema documents.
path=$(jq -r '.data.worktree.path // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
session="$waiting/${path//\//_}"

main() {
  [ -n "$workspace" ] && [ -n "$path" ] || exit 0
  pane=$(untouched_pane)
  [ -n "$pane" ] || exit 0
  command=$(joined "$(setup_command)" "$(waiting_session)")
  [ -n "$command" ] && "$herdr" pane run "$pane" "$command" >/dev/null
  rm -f "$session"
}

# The space's one pane; nothing when it has more, since then it is already in use.
untouched_pane() {
  local panes
  panes=$("$herdr" pane list --workspace "$workspace")
  [ "$(jq '.result.panes | length' <<<"$panes")" -eq 1 ] || return 0
  jq -r '.result.panes[0].pane_id' <<<"$panes"
}

# paseo.json lives in the main checkout, tracked or not, so it is read from there.
setup_command() {
  local common
  common=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ -f "$(dirname "$common")/paseo.json" ] || return 0
  jq -r '.worktree.setup // empty' "$(dirname "$common")/paseo.json" 2>/dev/null || true
}

waiting_session() {
  [ ! -f "$session" ] || cat "$session"
}

# "setup; session", or whichever of the two there is.
joined() {
  printf '%s' "$1${1:+${2:+; }}$2"
}

main
