#!/usr/bin/env bash
# Action shim: actions have no tty, so hand off to a plugin pane that does, at the placement
# its manifest gives it. Forwards the origin pane's cwd so the pane resolves the right repo,
# and the pane itself, since inside an overlay "the current pane" is the overlay.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

cwd=$(jq -r '.focused_pane_cwd // .workspace_cwd // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
args=(--plugin worktree --entrypoint new)
[ -n "$cwd" ] && args+=(--cwd "$cwd")
origin=$(jq -r '.focused_pane_id // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
[ -n "$origin" ] && args+=(--env "WORKTREE_ORIGIN_PANE=$origin")
exec "$herdr" plugin pane open "${args[@]}"
