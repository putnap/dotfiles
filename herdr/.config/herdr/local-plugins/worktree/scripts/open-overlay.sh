#!/usr/bin/env bash
# Action shim: actions have no tty, so hand off to an overlay pane that does.
# Forwards the origin pane's cwd so the overlay resolves the right repo.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
entrypoint=${1:?usage: open-overlay.sh <new|open>}

cwd=$(jq -r '.focused_pane_cwd // .workspace_cwd // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
args=(--plugin worktree --entrypoint "$entrypoint" --placement overlay)
[ -n "$cwd" ] && args+=(--cwd "$cwd")
exec "$herdr" plugin pane open "${args[@]}"
