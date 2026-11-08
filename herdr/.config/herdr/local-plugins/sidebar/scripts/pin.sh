#!/usr/bin/env bash
# Pins the focused agent to the top of the inbox, or unpins it, then reports at once so it
# moves now. Pins are kept by the agent's session id, which a restored agent keeps, and in
# the order they were made; an agent with no session id is pinned by its pane.
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
pins=${HERDR_PLUGIN_STATE_DIR:?}/pins

main() {
  local key
  key=$(focused_agent_key)
  if [[ -z $key ]]; then
    exec "$herdr" notification show "No agent to pin" --body "the focused pane runs no agent" --sound none
  fi
  toggle_pin "$key"
  exec bash "$(dirname "$0")/report.sh"
}

focused_agent_key() {
  local pane
  pane=$("$herdr" pane current | jq -r '.result.pane.pane_id')
  "$herdr" agent get "$pane" 2>/dev/null | jq -r '.result.agent | .agent_session.value // .pane_id // empty' || true
}

toggle_pin() {
  mkdir -p "${pins%/*}"
  touch "$pins"
  if grep -qxF -- "$1" "$pins"; then
    grep -vxF -- "$1" "$pins" > "$pins.$$" || true
    mv "$pins.$$" "$pins"
  else
    printf '%s\n' "$1" >> "$pins"
  fi
}

main
