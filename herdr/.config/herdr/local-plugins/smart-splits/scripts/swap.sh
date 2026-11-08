#!/usr/bin/env bash
# tmux's prefix+{ and prefix+}: swap the focused pane with the previous or next pane in
# layout order, wrapping around. herdr's own swaps are directional, so panes side by side
# never swap up or down.
#
# Usage: swap.sh <previous|next>
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
step="${1:?usage: swap.sh <previous|next>}"

case $step in
  previous) offset=-1 ;;
  next)     offset=1 ;;
  *) echo "swap.sh: bad argument: $step" >&2; exit 2 ;;
esac

layout=$("$herdr" pane layout --current)
source_pane="${HERDR_PANE_ID:-$(jq -r '.result.layout.focused_pane_id' <<<"$layout")}"
# jq's negative index counts from the end, which is the wrap from the first pane back.
target_pane=$(jq -r --arg source "$source_pane" --argjson offset "$offset" '
  [.result.layout.panes[].pane_id] as $order
  | select(($order | length) > 1)
  | $order[(($order | index($source)) + $offset) % ($order | length)]' <<<"$layout")

[ -n "$target_pane" ] || exit 0
exec "$herdr" pane swap --source-pane "$source_pane" --target-pane "$target_pane" >/dev/null
