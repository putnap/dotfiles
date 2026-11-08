#!/usr/bin/env bash
# Navigating back into a stacked column must land on the pane you came from, the
# way tmux does; herdr's own directional focus always picks the top one.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-smart-splits.XXXXXX)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
cat > "$HERDR_CONFIG_PATH" <<'CONFIG'
[ui.toast]
delivery = "off"
[ui.sound]
enabled = false
[terminal]
default_shell = "/bin/sh"
shell_mode = "non_login"
CONFIG
herdr server > "$scratch/server.log" 2>&1 &
server=$!
cleanup() {
  herdr server stop >/dev/null 2>&1 || kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
rpc() {
  jq -cn --arg method "$1" --argjson params "$2" '{id:"test",method:$method,params:$params}' |
    /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 |
    jq -e 'if .error then error(.error | tostring) else .result end'
}
for ((i=0;i<100;i++)); do
  [[ ! -S $HERDR_SOCKET_PATH ]] || break
  sleep 0.1
done
rpc ping '{}' >/dev/null

# Two columns, the left one split in two: top_left over bottom_left, right beside them.
top_left=$(rpc workspace.create "$(jq -cn --arg cwd "$scratch" '{cwd:$cwd,label:"nav"}')" | jq -er '.root_pane.pane_id')
right=$(rpc pane.split "$(jq -cn --arg pane "$top_left" --arg cwd "$scratch" '{target_pane_id:$pane,direction:"right",cwd:$cwd}')" | jq -er '.pane.pane_id')
bottom_left=$(rpc pane.split "$(jq -cn --arg pane "$top_left" --arg cwd "$scratch" '{target_pane_id:$pane,direction:"down",cwd:$cwd}')" | jq -er '.pane.pane_id')

focused() { rpc pane.list '{}' | jq -er '.panes[] | select(.focused) | .pane_id'; }
press() { HERDR_PANE_ID=$1 bash "$repo/herdr/.config/herdr/local-plugins/smart-splits/scripts/smart-splits.sh" nav "$2"; }
expect() {
  local want=$1 got=$2 what=$3
  [[ $got == "$want" ]] || { echo "$what: expected $want, got $got" >&2; exit 1; }
}

# herdr on its own: both left panes are candidates and it always takes the top.
rpc pane.focus "$(jq -cn --arg pane "$right" '{pane_id:$pane}')" >/dev/null
rpc pane.focus_direction "$(jq -cn --arg pane "$right" '{pane_id:$pane,direction:"left"}')" >/dev/null
expect "$top_left" "$(focused)" 'herdr directional focus'

# Through the plugin, the pane we came from wins instead.
press "$bottom_left" right
expect "$right" "$(focused)" 'bottom left -> right'
press "$right" left
expect "$bottom_left" "$(focused)" 'right -> back where we came from'

press "$top_left" right
expect "$right" "$(focused)" 'top left -> right'
press "$right" left
expect "$top_left" "$(focused)" 'right -> back to the top pane'

# An unambiguous move still goes through herdr, and the stamp follows the keypress.
press "$top_left" down
expect "$bottom_left" "$(focused)" 'top left -> bottom left'
press "$bottom_left" right
press "$right" left
expect "$bottom_left" "$(focused)" 'right -> most recent left pane'

# Past the leftmost pane there is nothing to move to: focus stays.
press "$bottom_left" left
expect "$bottom_left" "$(focused)" 'left edge keeps pane focus'

# tmux's order-based swaps: a pane on the right trades places with the next pane, wrapping
# round to the left column, and the previous swap puts it back.
column_of() { HERDR_PANE_ID=$1 herdr pane layout --current | jq -r --arg pane "$1" '.result.layout.panes[] | select(.pane_id == $pane) | .rect.x'; }
swap() { HERDR_PANE_ID=$1 bash "$repo/herdr/.config/herdr/local-plugins/smart-splits/scripts/swap.sh" "$2"; }
start_column=$(column_of "$right")
swap "$right" next
expect 0 "$(column_of "$right")" 'swap next moves the right pane to the left column'
swap "$right" previous
expect "$start_column" "$(column_of "$right")" 'swap previous puts it back'

printf '%s\n' 'smart-splits navigation passed: returns to the pane you came from, left edge stays, tmux swaps'

