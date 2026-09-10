#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
socket=${1:?}; terminal=${2:?}; generation=${3:?}; identity=${4:?}
[[ $generation == "$socket:$(/usr/bin/stat -f '%i:%B:%c' "$socket")" ]] || { echo 'notification belongs to a previous herdr server' >&2; exit 1; }
rpc() {
  jq -cn --arg method "$1" --argjson params "$2" '{id:"peon-focus",method:$method,params:$params}' |
    /usr/bin/nc -U -w 5 "$socket" | head -n 1 |
    jq -e 'if .error then error(.error | tostring) else .result end'
}
agent=$(rpc agent.list '{}' | jq -ce --arg terminal "$terminal" '.agents[] | select(.terminal_id == $terminal)')
jq -e --argjson identity "$identity" '[.agent,.agent_session] == $identity' <<< "$agent" >/dev/null || { echo 'notifying session has been replaced' >&2; exit 1; }
rpc agent.focus "$(jq -c '{target:.pane_id}' <<< "$agent")" >/dev/null
marker=herdr-peon-$(uuidgen)
rpc client.window_title.set "$(jq -cn --arg title "$marker" '{title:$title}')" | jq -e '.reason != "no_foreground_client"' >/dev/null
trap 'rpc client.window_title.clear "{}" >/dev/null' EXIT
for ((attempt=0; attempt<10; attempt++)); do
  if [[ $(osascript "$root/focus.applescript" "$marker") == found ]]; then exit 0; fi
  sleep 0.1
done
open -b com.mitchellh.ghostty
