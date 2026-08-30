#!/usr/bin/env bash
#
# herdr side of smart-splits.nvim. Derived from upstream's scripts/herdr-navigate.sh,
# extended to cover resize (upstream ships navigation only).
#
# Usage: smart-splits.sh <nav|resize> <left|down|up|right>
#
# Decision table per keypress:
#   1. Vim owns the focused pane -> forward the key, let smart-splits.nvim move or
#      resize the Neovim split and call back into herdr at a split edge.
#   2. Otherwise act on the herdr split. If nothing changed (no neighbor, or the
#      pane fills the tab), send the key back so shell defaults survive --
#      C-l clears, C-h backspaces, C-Left/C-Right move by word.

set -euo pipefail

mode="${1:?usage: smart-splits.sh <nav|resize> <left|down|up|right>}"
dir="${2:?usage: smart-splits.sh <nav|resize> <left|down|up|right>}"
herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_PANE_ID:-}"

case "$mode:$dir" in
  nav:left)     key="ctrl+h" ;;
  nav:down)     key="ctrl+j" ;;
  nav:up)       key="ctrl+k" ;;
  nav:right)    key="ctrl+l" ;;
  resize:left)  key="ctrl+left" ;;
  resize:down)  key="ctrl+down" ;;
  resize:up)    key="ctrl+up" ;;
  resize:right) key="ctrl+right" ;;
  *) echo "smart-splits.sh: bad arguments: $mode $dir" >&2; exit 2 ;;
esac

# Foreground process names meaning "Vim is in control of this pane".
# Same matcher vim-tmux-navigator uses: vi, vim, nvim, view, gvim, *diff, ...
vim_re='^g?(view|l?n?vim?x?)(diff)?$'
# Opt-in passthrough for other TUIs that own these keys themselves,
# e.g. SMART_SPLITS_HERDR_PASSTHROUGH_RE='^(lazygit|k9s)$'
passthrough_re="${SMART_SPLITS_HERDR_PASSTHROUGH_RE:-}"

send_back() { exec "$herdr" pane send-keys "$pane" "$key"; }

if [ -n "$pane" ] && command -v jq >/dev/null 2>&1; then
  if "$herdr" pane process-info --current 2>/dev/null \
    | jq -e --arg vim "$vim_re" --arg pass "$passthrough_re" \
        '.result.process_info.foreground_processes[]?.name
         | ascii_downcase
         | select(test($vim) or ($pass != "" and (try test($pass) catch false)))' >/dev/null 2>&1; then
    send_back
  fi
fi

if [ "$mode" = nav ]; then
  output=$("$herdr" pane focus --direction "$dir" --current 2>/dev/null) || send_back
  field='.result.focus.changed'
else
  output=$("$herdr" pane resize --direction "$dir" --current 2>/dev/null) || send_back
  field='.result.resize.changed'
fi

if command -v jq >/dev/null 2>&1 &&
  [ "$(printf '%s' "$output" | jq -r "$field // false" 2>/dev/null)" = true ]; then
  exit 0
fi
send_back
