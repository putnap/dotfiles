#!/usr/bin/env bash
# Marks the focused agent's reply read, for one that needs nothing back: it leaves the inbox and
# its title dims. Its next turn would clear the mark anyway. Reports at once so it moves now.
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}

main() {
  local pane
  pane=$("$herdr" pane current | jq -r '.result.pane.pane_id')
  "$herdr" pane report-metadata "$pane" --source plugin:sidebar --token unread= --token reason= >/dev/null
  exec bash "$(dirname "$0")/report.sh"
}

main
