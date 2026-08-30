#!/usr/bin/env bash
# Rows for herdr's currently open workspaces, with live agent status.
# Split out so picker.sh can reuse one query for both the initial render and
# the open-path filter, instead of asking herdr the same thing twice.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
workspaces=$("$herdr" workspace list)
panes=$("$herdr" pane list)

jq -rn --argjson ws "$workspaces" --argjson pn "$panes" '
  # A workspace has no cwd of its own; take it from its first pane.
  ($pn.result.panes | group_by(.workspace_id)
   | map({key: .[0].workspace_id, value: .[0].cwd}) | from_entries) as $cwd
  | $ws.result.workspaces[]
  | . as $w
  | (if   .agent_status == "blocked" then "◉"
     elif .agent_status == "working" then "◐"
     elif .agent_status == "done"    then "✓"
     elif .agent_status == "idle"    then "○"
     else "·" end) as $icon
  | ($w.worktree.checkout_path // $cwd[$w.workspace_id] // "") as $path
  | "\($icon) \(.label)\t\($path)\t\(.workspace_id)"'
