#!/usr/bin/env bash
# Move the focused pane out into its own tab, or its own workspace.
#
# tmux's break-pane and Vim's <C-w>T. herdr has no built-in action for it, and
# `herdr pane move` takes an explicit pane id rather than --current, so resolve
# the focused pane first the way agent-fork.sh does.
#
# Usage: break-pane.sh [tab|workspace]
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
target="${1:-tab}"

pane=$("$herdr" pane current | jq -r '.result.pane.pane_id // empty')
[ -n "$pane" ] || { "$herdr" notification show "No pane" --body "Could not resolve the focused pane." --sound none; exit 1; }

case "$target" in
  tab)       exec "$herdr" pane move "$pane" --new-tab --focus ;;
  workspace) exec "$herdr" pane move "$pane" --new-workspace --focus ;;
  *) echo "break-pane.sh: expected tab or workspace, got $target" >&2; exit 2 ;;
esac
