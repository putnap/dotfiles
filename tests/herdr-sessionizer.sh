#!/usr/bin/env bash
# prefix+s's picker opens as a popup over the layout, through a temporary server: the action
# runs and no pane is added, where the old overlay added one.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-sessionizer.XXXXXX)
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
for ((i=0;i<100;i++)); do
  [[ ! -S $HERDR_SOCKET_PATH ]] || break
  sleep 0.1
done
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/sessionizer" >/dev/null
herdr workspace create --cwd "$scratch" --label home >/dev/null

expect() {
  if [[ $2 != "$1" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$3" "$1" "$2" >&2
    exit 1
  fi
}
pane_count() { herdr pane list | jq '.result.panes | length'; }

herdr plugin action invoke sessionizer.open >/dev/null
for ((i=0;i<50;i++)); do
  [[ $(herdr plugin log list --plugin sessionizer | jq '[.result.logs[] | select(.status == "succeeded")] | length') == 0 ]] || break
  sleep 0.1
done
expect 1 "$(herdr plugin log list --plugin sessionizer | jq '[.result.logs[] | select(.status == "succeeded")] | length')" 'the open action succeeded'
expect 1 "$(pane_count)" 'the picker added no pane'
printf '%s\n' 'sessionizer passed: prefix+s opens the picker as a popup'
