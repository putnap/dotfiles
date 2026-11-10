#!/usr/bin/env bash
# ctrl+? (and ctrl+\ ?): every key, keys.json's and the ones after ctrl+\, in one fzf list, as the
# worktree picker. The keys mod passes the rows ("action<TAB>shown") and, once this has exited,
# runs the action written to the choice file, so it acts on the pane under the popup.
set -euo pipefail

rows=$1
choice=$2
: >"$choice"
picked=$(printf '%s\n' "$rows" | fzf --exact --no-multi --height=100% \
  --delimiter='\t' --with-nth=2 \
  --prompt='keys> ' \
  --header='prefix is ctrl+\ · enter: run it · esc: close') || exit 0
cut -f1 <<<"$picked" >"$choice"
