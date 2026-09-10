#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd "$(dirname "$0")" && pwd -P)
root=${HERDR_FOOTER_STATE_DIR:?}
unset CODEX_THREAD_ID
# Also cover an already-running preview server that inherited NO_COLOR at startup.
unset NO_COLOR
case ${1:?} in
  claude)
    mkdir -p "$root"
    jq -n --arg command "bash '$scripts/claude-cache.sh'" '{statusLine:{type:"command",command:$command}}' > "$root/claude-settings.json"
    args=(--dangerously-skip-permissions --settings "$root/claude-settings.json")
    if [[ -n ${HERDR_FOOTER_CLAUDE_RESUME:-} ]]; then
      args+=(--resume "$HERDR_FOOTER_CLAUDE_RESUME")
    fi
    exec claude "${args[@]}"
    ;;
  codex)
    if [[ -n ${HERDR_FOOTER_CODEX_RESUME:-} ]]; then
      exec codex -c 'tui.status_line=[]' resume "$HERDR_FOOTER_CODEX_RESUME"
    fi
    exec codex -c 'tui.status_line=[]';;
  *) exit 2;;
esac
