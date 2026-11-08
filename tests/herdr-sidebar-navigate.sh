#!/usr/bin/env bash
# shift+up/down through the sidebar plugin, linked into a temporary server: one loop through
# the tree's order, landing on every agent and on a space only when it has none, then the inbox
# of blocked, done and unread agents, then round again. The inbox keeps the order it had on
# entering it. A focus moved some other way, as a click would, is where the next press starts.
# A press redraws the pointer itself, with the focus change, not after the focus hook.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-navigate.XXXXXX)
# Resolved, because git reports /tmp checkouts by their real /private/tmp path. Separate from
# mktemp, so its failure stops the script instead of resolving the current directory.
scratch=$(cd "$scratch" && pwd -P)
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
mkdir -p "$scratch/bin"
printf '#!/bin/sh\nexit 1\n' > "$scratch/bin/gh"
chmod +x "$scratch/bin/gh"
git init -q -b main "$scratch/app"
git -C "$scratch/app" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$scratch/app" worktree add -q -b feature/side "$scratch/app-side"
mkdir -p "$scratch/notes" "$scratch/empty"
PATH=$scratch/bin:$PATH herdr server > "$scratch/server.log" 2>&1 &
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
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/sidebar" >/dev/null

# notes: a shell and an agent. app: a shell and an agent in the main checkout, and an agent in
# its worktree, which has no shell of its own. empty: a shell and no agent.
notes_shell=$(herdr workspace create --cwd "$scratch/notes" --label notes | jq -er '.result.root_pane.pane_id')
notes_agent=$(herdr pane split "$notes_shell" --direction right --cwd "$scratch/notes" | jq -er '.result.pane.pane_id')
app_shell=$(herdr workspace create --cwd "$scratch/app" --label app | jq -er '.result.root_pane.pane_id')
app_agent=$(herdr pane split "$app_shell" --direction right --cwd "$scratch/app" | jq -er '.result.pane.pane_id')
side_agent=$(herdr pane split "$app_agent" --direction down --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
empty_shell=$(herdr workspace create --cwd "$scratch/empty" --label empty | jq -er '.result.root_pane.pane_id')
agent_state() { herdr pane report-agent "$1" --source custom:test --agent claude --state "$2" >/dev/null; }
for pane in "$app_agent" "$side_agent" "$notes_agent"; do agent_state "$pane" idle; done

focused() { herdr api snapshot | jq -r '.result.snapshot.focused_pane_id'; }
click() {
  jq -cn --arg pane "$1" '{id: "test", method: "pane.focus", params: {pane_id: $pane}}' |
    /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
  wait_for "$1" focused
}
# wait_for WANT COMMAND...: plugin runs are asynchronous, so poll until COMMAND prints WANT.
wait_for() {
  local want=$1 got
  shift
  for ((i=0;i<100;i++)); do
    got=$("$@")
    [[ $got != "$want" ]] || return 0
    sleep 0.1
  done
  echo "$*: expected $want, got $got" >&2
  herdr plugin log list | jq -r '.result.logs[] | select(.plugin_id == "sidebar" and .status == "failed") | .stderr' | tail -n 5 >&2
  exit 1
}
navigation_running() {
  herdr plugin log list |
    jq -r '[.result.logs[] | select(.command[1] == "scripts/navigate.sh" and .status == "running")] | length'
}
sidebar_running() {
  herdr plugin log list | jq -r '[.result.logs[] | select(.plugin_id == "sidebar" and .status == "running")] | length'
}
# press DIRECTION WANT: one shift+down or shift+up, which must land on the pane WANT. It waits
# for the redraws to settle first, so the press goes as they planned it; press_at_once doesn't,
# so the press finds no plan from where the focus is and works it out itself.
press() {
  wait_for 0 sidebar_running
  press_at_once "$@"
}
press_at_once() {
  herdr plugin action invoke "sidebar.$1" >/dev/null
  wait_for "$2" focused
  wait_for 0 navigation_running
}

# One blocked agent, then one done out of sight: the inbox is the done one, then the blocked.
# The done one's reply stays unread once seen, so it stays in the inbox.
click "$notes_shell"
agent_state "$app_agent" blocked
agent_state "$side_agent" working
agent_state "$side_agent" idle
unread() { herdr agent list | jq -r --arg pane "$1" '.result.agents[] | select(.pane_id == $pane) | .tokens.unread // ""'; }
wait_for ✓ unread "$side_agent"

# From the last row of the tree into the inbox, through it in that order, and round to the
# first stop, notes' agent.
click "$empty_shell"
press next "$side_agent"
press next "$app_agent"
press next "$notes_agent"
# Back from the first stop into the inbox's last agent, back through it, and on back to the
# tree's last row.
press previous "$app_agent"
press previous "$side_agent"
press previous "$empty_shell"

# The tree in drawn order from a shell in a space with agents: that space's row is passed over,
# the worktree's agent is reached (the worktree has no shell to open), and the space with no
# agents is a stop. The pointer is on the landing's row as soon as the press is done.
pointer() {
  herdr workspace list | jq -r --arg label "$1" '.result.workspaces[] | select(.label == $label) | .tokens // {}
    | to_entries[] | select((.key | test("^row_[0-9]+$")) and (.value | contains("▸"))) | .key'
}
expect_pointer() {
  [[ $(pointer "$1") == "$2" ]] || { echo "pointer in $1: expected $2, got $(pointer "$1")" >&2; exit 1; }
}
click "$app_shell"
press_at_once next "$app_agent"
expect_pointer app row_1
press next "$side_agent"
expect_pointer app row_3
press next "$empty_shell"
press previous "$side_agent"
click "$app_shell"
press previous "$notes_agent"

# Every run succeeds.
sidebar_runs() { herdr plugin log list | jq '[.result.logs[] | select(.plugin_id == "sidebar")]'; }
for ((i=0;i<100;i++)); do
  sidebar_runs | jq -e 'all(.[]; .status != "running")' >/dev/null && break
  sleep 0.1
done
sidebar_runs | jq -e 'all(.[]; .status == "succeeded")' >/dev/null ||
  { sidebar_runs | jq -c 'first(.[] | select(.status != "succeeded"))' >&2; exit 1; }
printf '%s\n' 'sidebar navigation passed: tree in drawn order past spaces with agents, pointer drawn with the press, into the inbox and through it as it was, round both ways, on from a click'
