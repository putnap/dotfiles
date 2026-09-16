#!/usr/bin/env bash
set -euo pipefail
[[ -n ${TMUX:-} && -n ${TMUX_PANE:-} && -z ${WORKMUX_DISABLE_SET_WINDOW_STATUS:-} ]] || exit 0
# Existing tmux shells may retain herdr variables from the server's launch environment.
unset HERDR_SOCKET_PATH HERDR_PANE_ID
command -v workmux >/dev/null || exit 0
provider=${1:?}; action=${2:?}
input=$(cat)
# Nested agents must not replace the top-level pane's identity or status.
[[ $(jq -r '.agent_id // empty' <<< "$input") == '' ]] || exit 0
session=$(jq -er '.session_id | select(test("^[a-zA-Z0-9_-]+$"))' <<< "$input")
identity=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_pid} #{pane_current_command}')
previous=$(tmux show-options -pqv -t "$TMUX_PANE" @workmux_hook)
record=$(jq -cn --arg provider "$provider" --arg session "$session" --arg identity "$identity" --arg status "$action" \
  '{provider:$provider,session:$session,identity:$identity,status:$status}')
tmux set-option -p -t "$TMUX_PANE" @workmux_hook "$record"
if [[ $action == register ]]; then
  workmux register-agent <<< "$input"
  if [[ $(tmux show-options -gqv @workmux_restoring) != on ]]; then
    workmux sidebar --session on </dev/null
  fi
else workmux set-window-status "$action" <<< "$input"; fi
case "$action" in
  done|waiting)
    # Repeated hooks in one state must not play the completion sound twice.
    if jq -e --argjson current "$record" '. == $current' <<< "${previous:-null}" >/dev/null; then exit 0; fi
    notification=idle_prompt
    [[ $action != waiting ]] || notification=elicitation_dialog
    jq --arg notification "$notification" --arg provider "$provider" \
      '. + {hook_event_name:"Notification",notification_type:$notification,source:$provider}' <<< "$input" |
      bash /opt/homebrew/opt/peon-ping/libexec/peon.sh
    ;;
esac
