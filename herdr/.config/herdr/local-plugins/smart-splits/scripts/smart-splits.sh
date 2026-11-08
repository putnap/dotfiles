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
#      The key sent back must match keymaps.lua: resize is <C-S-arrow>, since
#      plain <C-arrow> is word motion now.
#   2. Otherwise act on the herdr split. If nothing changed (no neighbor, or the
#      pane fills the tab), send the key back so shell defaults survive --
#      C-l clears, C-h backspaces, C-Left/C-Right move by word (bound in .zshrc).

set -euo pipefail

mode="${1:?usage: smart-splits.sh <nav|resize> <left|down|up|right>}"
dir="${2:?usage: smart-splits.sh <nav|resize> <left|down|up|right>}"
herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_PANE_ID:-}"
sock="${HERDR_SOCKET_PATH:-}"
# When a move has several candidate panes herdr always picks the first one, so
# stepping back from a wide pane lands on the top of a stacked column rather than
# where you left. tmux picks the most recently used candidate instead; this list
# is how we match it. Keyed by socket, so each herdr server keeps its own.
mru_file="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/smart-splits/${sock//\//_}.mru"

case "$mode:$dir" in
  nav:left)     key="ctrl+h" ;;
  nav:down)     key="ctrl+j" ;;
  nav:up)       key="ctrl+k" ;;
  nav:right)    key="ctrl+l" ;;
  resize:left)  key="ctrl+shift+left" ;;
  resize:down)  key="ctrl+shift+down" ;;
  resize:up)    key="ctrl+shift+up" ;;
  resize:right) key="ctrl+shift+right" ;;
  *) echo "smart-splits.sh: bad arguments: $mode $dir" >&2; exit 2 ;;
esac

# Foreground process names meaning "Vim is in control of this pane".
# Same matcher vim-tmux-navigator uses: vi, vim, nvim, view, gvim, *diff, ...
vim_re='^g?(view|l?n?vim?x?)(diff)?$'
# Opt-in passthrough for other TUIs that own these keys themselves,
# e.g. SMART_SPLITS_HERDR_PASSTHROUGH_RE='^(lazygit|k9s)$'
passthrough_re="${SMART_SPLITS_HERDR_PASSTHROUGH_RE:-}"

send_back() { exec "$herdr" pane send-keys "$pane" "$key"; }

mru_ready() {
  [ -n "$pane" ] && [ -n "$sock" ] &&
    command -v jq >/dev/null 2>&1 && [ -x /usr/bin/nc ]
}

record_mru() {
  local rest=''
  mkdir -p "${mru_file%/*}"
  if [ -f "$mru_file" ]; then
    rest=$(grep -vxF -- "$pane" "$mru_file" | head -n 31) || true
  fi
  if [ -n "$rest" ]; then
    printf '%s\n%s\n' "$pane" "$rest" >"$mru_file"
  else
    printf '%s\n' "$pane" >"$mru_file"
  fi
}

# The most recently visited of the panes herdr has to choose between. Neighbors
# are the nearest panes on that side that overlap this one; fewer than two of
# them means herdr has no choice to get wrong, and zoom is left to herdr.
mru_pick() {
  local candidates
  candidates=$("$herdr" pane layout --current 2>/dev/null | jq -r --arg cur "$pane" --arg dir "$dir" '
    .result.layout
    | select(.zoomed | not)
    | .panes as $panes
    | ($panes[] | select(.pane_id == $cur) | .rect) as $c
    | [ $panes[]
        | select(.pane_id != $cur)
        | { id: .pane_id,
            gap: (if $dir == "left" then $c.x - (.rect.x + .rect.width)
                  elif $dir == "right" then .rect.x - ($c.x + $c.width)
                  elif $dir == "up" then $c.y - (.rect.y + .rect.height)
                  else .rect.y - ($c.y + $c.height) end),
            overlaps: (if $dir == "left" or $dir == "right"
                       then .rect.y < $c.y + $c.height and $c.y < .rect.y + .rect.height
                       else .rect.x < $c.x + $c.width and $c.x < .rect.x + .rect.width end) }
        | select(.overlaps and .gap >= 0) ]
    | (map(.gap) | min) as $nearest
    | .[] | select(.gap == $nearest) | .id') || return 1
  [ "$(printf '%s' "$candidates" | grep -c .)" -gt 1 ] || return 1
  grep -m1 -xF -f <(printf '%s\n' "$candidates") "$mru_file" 2>/dev/null
}

# No CLI focuses a pane by id, so ask the API socket directly.
focus_pane() {
  jq -cn --arg pane "$1" '{id:"smart-splits:focus",method:"pane.focus",params:{pane_id:$pane}}' |
    /usr/bin/nc -U -w 1 "$sock" | head -n 1 | jq -e '.result' >/dev/null 2>&1
}

# Stamp first: whatever the key ends up doing, this pane is the one just used.
if mru_ready; then record_mru; fi

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
  if mru_ready && target=$(mru_pick); then
    if focus_pane "$target"; then exit 0; fi
  fi
  output=$("$herdr" pane focus --direction "$dir" --current 2>/dev/null) || send_back
  field='.result.focus.changed'
else
  # Without --amount herdr uses its own default, which moves about a quarter of
  # the screen a press. Matches keymaps.lua's default_amount in feel.
  output=$("$herdr" pane resize --direction "$dir" --amount 0.03 --current 2>/dev/null) || send_back
  field='.result.resize.changed'
fi

if command -v jq >/dev/null 2>&1 &&
  [ "$(printf '%s' "$output" | jq -r "$field // false" 2>/dev/null)" = true ]; then
  exit 0
fi
send_back
