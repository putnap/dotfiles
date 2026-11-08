#!/usr/bin/env bash
# Action shim: actions run without a tty, so hand off to the picker's popup pane.
set -euo pipefail
herdr="${HERDR_BIN_PATH:-herdr}"
cwd=$(jq -r '.focused_pane_cwd // .workspace_cwd // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
args=(--plugin sessionizer --entrypoint picker)
[ -n "$cwd" ] && args+=(--cwd "$cwd")
exec "$herdr" plugin pane open "${args[@]}"
