#!/usr/bin/env bash
# shift+up/down: one loop through the sidebar's tree in drawn order, then through the inbox
# below it, then round to the top again. A press lands on each agent, and on a space or worktree
# only when it has no agents; one with agents is already reached through them.
# The inbox is kept as it was on entering it, so an agent leaving it mid-walk isn't skipped.
# Each press saves where it landed. When the focus has since moved some other way (a click,
# a notification, another key) the next press starts from wherever the focus is now.
# Every row opens a pane (tree.jq's target), so landing is always focusing one. The rows that
# change go with the focus change, so the pointer moves with the screen. Every redraw plans both
# presses ahead (report.sh), so a press from where that redraw was only sends them.
#
# Usage: navigate.sh <next|previous>   a press
#        navigate.sh landings PANE     where each press lands from PANE, the tree on stdin
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
cursor_file=${HERDR_PLUGIN_STATE_DIR:?}/cursor.json
source "$(dirname "$0")/tree.sh"

# Every row of the tree in drawn order, `stop` marking the ones a press lands on. The rows
# passed over stay, so a press from a focused shell still knows where it is.
rows_query='
  def opens_without_agents: .target != null and ([.agents[], .groups[]?.agents[]] | length) == 0;
  def agent_row: {key: "agent:\(.pane_id)", pane: .pane_id, here, stop: true};
  [.spaces[] | {key: "space:\(.workspace_id)", pane: .target, here, stop: opens_without_agents},
     (.agents[] | agent_row),
     (.groups[] | {key: "group:\(.workspace_id):\(.checkout)", pane: .target, here, stop: opens_without_agents},
                  (.agents[] | agent_row))]'

# Input: {rows, inbox}. $cursor: the last landing, or null when the focus has moved since.
# landing(1) is where the next press lands, landing(-1) the previous: {list, key, pane, queue}.
landing_query='
  def position($list; $key): $list | map(.key) | index($key);
  def tree_landing($stop): $stop + {list: "tree"};
  def inbox_landing($queue; $key): {list: "inbox", key: $key, pane: ($key | ltrimstr("agent:")), queue: $queue};
  def landing($step):
    def rows_ahead($rows; $at): if $step > 0 then $rows[$at + 1:] else $rows[:$at] | reverse end;
    .rows as $rows
    | [$rows[] | select(.stop)] as $stops
    | [.inbox[] | "agent:\(.)"] as $inbox
    | (if $step > 0 then $stops[0] else $stops[-1] end) as $wrap
    | if $cursor.list == "inbox" then
        [$cursor.queue[] | select(IN($stops[].key))] as $queue
        | (position($queue | map({key: .}); $cursor.key) // -1) as $at
        | (if $step > 0 then $queue[$at + 1:] else $queue[:([$at, 0] | max)] | reverse end) as $ahead
        | if ($ahead | length) > 0 then inbox_landing($cursor.queue; $ahead[0]) else tree_landing($wrap) end
      else
        (if $cursor != null then $cursor.key else first($rows[] | select(.here) | .key) end) as $key
        | position($rows; $key) as $at
        | (if $at == null then null else first(rows_ahead($rows; $at)[] | select(.stop)) // null end) as $next
        | if $at == null then tree_landing($wrap)
          elif $next != null then tree_landing($next)
          elif ($inbox | length) > 0 then inbox_landing($inbox; if $step > 0 then $inbox[0] else $inbox[-1] end)
          else tree_landing($wrap) end
      end;'

main() {
  case ${1:?usage: navigate.sh <next|previous|landings>} in
    next | previous) press "$1" ;;
    landings) landings "$(cat)" "$2" ;;
    *) echo "navigate.sh: unknown command: $1" >&2; exit 2 ;;
  esac
}

press() {
  local plan
  plan=$(planned "$1")
  if [[ -z $plan ]]; then plan=$(plan_now "$1"); fi
  if [[ -n $plan ]]; then go "$plan"; fi
}

# The press as the last redraw planned it, if that redraw was from where the focus is now.
planned() {
  jq -c --arg from "${HERDR_PANE_ID:-}" --arg direction "$1" \
    'select(.from == $from) | .[$direction] | values' "$plans_file" 2>/dev/null || true
}

# No plan from here yet, as when the focus has only just moved: the same, worked out now.
plan_now() {
  local snapshot landing tokens
  snapshot=$("$herdr" api snapshot | jq '.result.snapshot')
  landing=$(landings "$(tree "$snapshot")" "${HERDR_PANE_ID:-}" | jq -c --arg direction "$1" '.[$direction] | values')
  if [[ -z $landing ]]; then return 0; fi
  tokens=$(bash "$(dirname "$0")/report.sh" rows-for "$(jq -r '.pane' <<< "$landing")" <<< "$snapshot")
  jq -cn --argjson landing "$landing" --argjson tokens "$tokens" '{landing: $landing, tokens: $tokens}'
}

# The landing is kept before the focus moves, so the focus hook plans the next press from it.
go() {
  local landing pane tokens focusing
  { IFS= read -r landing; IFS= read -r pane; IFS= read -r tokens; } \
    < <(jq -r '(.landing | tojson), .landing.pane, (.tokens | tojson)' <<< "$1")
  save_cursor "$landing"
  focus_pane "$pane" &
  focusing=$!
  send_tokens "$(report_sequence)" <<< "$tokens"
  wait "$focusing"
}

# landings TREE FOCUSED: {next, previous}.
landings() {
  jq -c --argjson cursor "$(cursor_if_still_on "$2")" \
    "{rows: ($rows_query), inbox: .inbox} | $landing_query {next: landing(1), previous: landing(-1)}" <<< "$1"
}

# The saved landing, unless the focus has left the pane it opened.
cursor_if_still_on() {
  if [[ -f $cursor_file ]] && jq -e --arg focused "$1" '.pane == $focused' "$cursor_file" >/dev/null; then
    cat "$cursor_file"
  else
    printf null
  fi
}

# Any pane, agent or not, in any space; herdr's CLI only focuses agents or neighbours.
focus_pane() {
  send_request "$(printf '{"id":"sidebar:navigate","method":"pane.focus","params":{"pane_id":"%s"}}' "$1")"
}

save_cursor() {
  printf '%s\n' "$1" > "$cursor_file.$$"
  mv "$cursor_file.$$" "$cursor_file"
}

main "$@"
