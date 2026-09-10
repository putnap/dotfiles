#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd -P)
socket=${HERDR_SOCKET_PATH:?}
generation="$socket:$(/usr/bin/stat -f '%i:%B:%c' "$socket")"
key=$(printf '%s' "$generation" | shasum -a 256 | cut -c1-24)
state_dir=${HERDR_PLUGIN_STATE_DIR:?}
mkdir -p "$state_dir"
# macOS shlock reclaims locks after their owning process exits.
lock=$state_dir/$key.lock
locked=false
for ((attempt=0; attempt<400; attempt++)); do
  if /usr/bin/shlock -p "$$" -f "$lock"; then locked=true; break; fi
  sleep 0.1
done
[[ $locked == true ]] || { echo 'peon: state lock timeout' >&2; exit 1; }
tmp=$(mktemp "$state_dir/.transition.XXXXXX")
trap 'rm -f "$lock" "$tmp"' EXIT
agents=$("${HERDR_BIN_PATH:-herdr}" agent list | jq -e '.result.agents')
state=$state_dir/$key.json
[[ -f $state ]] || printf '{}\n' > "$state"
if [[ ${1:-} == seed ]]; then
  jq --argjson agents "$agents" 'reduce $agents[] as $a (. ; .[$a.terminal_id] = ([.[$a.terminal_id] // -1, $a.state_change_seq] | max))' "$state" > "$tmp"
  mv "$tmp" "$state"
  exit 0
fi
event=${HERDR_PLUGIN_EVENT_JSON:-null}
agent=$(jq -c --argjson event "$event" '.[] | select(.pane_id == $event.data.pane_id and .agent_status == $event.data.agent_status)' <<< "$agents")
[[ -n $agent ]] || exit 0
terminal=$(jq -er '.terminal_id' <<< "$agent")
seq=$(jq -er '.state_change_seq' <<< "$agent")
old=$(jq -r --arg terminal "$terminal" '.[$terminal] // -1' "$state")
((seq > old)) || exit 0
jq --arg terminal "$terminal" --argjson seq "$seq" '.[$terminal] = $seq' "$state" > "$tmp"
mv "$tmp" "$state"
case $(jq -r '.agent_status' <<< "$agent") in
  done) notification=idle_prompt;;
  blocked) notification=elicitation_dialog;;
  *) exit 0;;
esac
identity=$(jq -c '[.agent, .agent_session]' <<< "$agent")
printf -v PEON_CLICK_COMMAND '%q ' bash "$root/focus.sh" "$socket" "$terminal" "$generation" "$identity"
export PEON_CLICK_COMMAND
jq -cn --argjson agent "$agent" --arg notification "$notification" --arg session "herdr-$key-$terminal" --arg home "$HOME" \
  '{hook_event_name:"Notification", notification_type:$notification, cwd:($agent.cwd // $home), session_id:$session, source:($agent.agent // "herdr")}' |
  bash /opt/homebrew/opt/peon-ping/libexec/peon.sh
