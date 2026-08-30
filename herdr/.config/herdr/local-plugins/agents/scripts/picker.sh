#!/usr/bin/env bash
# Pick an agent and focus it.
#
# `herdr agent list` already carries everything a row needs, and `herdr agent
# read` prints plain text straight to stdout, so the preview is one fzf flag.
#
# Rows are sorted by state_change_seq -- a monotonic counter herdr bumps on
# every agent state transition -- so whatever just moved sits at the top.
# The status is a glyph rather than a word to leave room for the title, which
# is the only thing distinguishing three `claude` sessions in one repo.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

rows() {
  "$herdr" agent list | jq -r '
    .result.agents
    | sort_by(-.state_change_seq)
    | .[]
    | [ (.agent_status
          | if . == "blocked" then "!"
            elif . == "working" then "~"
            elif . == "done"    then "*"
            else " " end)
        + "  " + .agent
        + "  " + (.terminal_title_stripped // "-")
        + "  (" + (.cwd | split("/") | last) + ")",
        .pane_id ]
    | @tsv'
}

listing=$(rows)
if [ -z "$listing" ]; then
  exec "$herdr" notification show "No agents" --body "Nothing is running." --sound none
fi

choice=$(printf '%s\n' "$listing" |
  fzf --delimiter='\t' --with-nth=1 --no-multi --height=100% \
      --prompt='agent> ' --header='! blocked   ~ working   * done      enter: focus' \
      --preview="$herdr agent read {2} --source visible --lines 60" \
      --preview-window=right:60%) || exit 0

exec "$herdr" agent focus "$(cut -f2 <<<"$choice")"
