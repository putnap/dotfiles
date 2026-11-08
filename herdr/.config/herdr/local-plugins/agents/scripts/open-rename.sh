#!/usr/bin/env bash
# Action shim: actions have no tty, so hand off to the rename popup, naming the pane it is for,
# since inside the popup "the current pane" is the popup.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

pane=$(jq -r '.focused_pane_id // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
[ -n "$pane" ] || exit 0
exec "$herdr" plugin pane open --plugin agents --entrypoint rename --env "RENAME_PANE=$pane"
