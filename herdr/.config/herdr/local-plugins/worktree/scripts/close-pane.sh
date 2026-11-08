#!/usr/bin/env bash
# prefix+x: closes the focused pane at once, unless it is its space's last, when the close
# dialog (close-space.sh) asks first, as herdr's own close_pane does with confirm_close.
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
pane=${HERDR_PANE_ID:-}
workspace=${HERDR_WORKSPACE_ID:-}

panes_in() {
  "$herdr" pane list --workspace "$1" | jq '.result.panes | length'
}

if [[ -z $pane || -z $workspace ]]; then exit 0; fi
if [[ $(panes_in "$workspace") -gt 1 ]]; then
  "$herdr" pane close "$pane" >/dev/null
else
  "$herdr" plugin pane open --plugin worktree --entrypoint close --env "CLOSE_WORKSPACE=$workspace" >/dev/null
fi
