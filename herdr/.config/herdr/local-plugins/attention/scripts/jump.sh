#!/usr/bin/env bash
# Focus the agent that wants you: `blocked` (waiting on an answer) first, then
# `done` (finished while you were elsewhere), each most-recent-first.
#
# state_change_seq is a monotonic counter herdr bumps on every agent state
# transition, so it orders events by when they actually happened -- unlike
# agent_panel_sort = "priority", which only ranks by state.
#
# Pressing again cycles: if the focused pane is already in the queue, go to the
# next entry and wrap. That needs no stored state, and focusing a `done` agent
# marks it seen, so it drops out of the queue on its own.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

queue=$("$herdr" agent list | jq -r '
  [.result.agents[]
   | select(.agent_status == "blocked" or .agent_status == "done")]
  | sort_by([(if .agent_status == "blocked" then 0 else 1 end), -.state_change_seq])
  | .[].pane_id')

if [ -z "$queue" ]; then
  exec "$herdr" notification show "Nothing waiting" \
    --body "No agent is blocked or done." --sound none
fi

current=$("$herdr" pane current | jq -r '.result.pane.pane_id // empty')

# Avoid mapfile: herdr resolves `bash` from PATH and may find macOS's 3.2.
entries=()
while IFS= read -r line; do entries+=("$line"); done <<<"$queue"

target=${entries[0]}
for i in "${!entries[@]}"; do
  if [ "${entries[$i]}" = "$current" ]; then
    target=${entries[$(((i + 1) % ${#entries[@]}))]}
    break
  fi
done

exec "$herdr" agent focus "$target"
