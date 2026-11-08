#!/usr/bin/env bash
# The worktree plugin, linked into a temporary server: an agent started in a worktree's folder
# from another space moves into that worktree's own space, opened nested under its repository
# with the agent as its one pane, and a second such agent joins it in a new tab, taking
# the view with it when it had the focus. A shell in the worktree's folder and an agent in the
# main checkout stay where they are.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-adopt.XXXXXX)
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
git init -q -b main "$scratch/app"
git -C "$scratch/app" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
# Made the way agents make them, with plain git, so herdr has never heard of it.
git -C "$scratch/app" worktree add -q -b feature/eng-5-side "$scratch/app-side"
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
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/worktree" >/dev/null

agent_state() { herdr pane report-agent "$1" --source custom:test --agent claude --state idle >/dev/null; }
space_of_pane() { herdr pane get "$1" | jq -r '.result.pane.workspace_id'; }
side_space() { herdr workspace list | jq -r --arg checkout "$scratch/app-side" 'first(.result.workspaces[] | select(.worktree.checkout_path == $checkout) | .workspace_id) // ""'; }
panes_in() { herdr pane list --workspace "$1" | jq '.result.panes | length'; }
tabs_in() { herdr tab list --workspace "$1" | jq '.result.tabs | length'; }
focused() { herdr api snapshot | jq -r '.result.snapshot.focused_pane_id'; }
# wait_for WANT COMMAND...: hooks run asynchronously, so poll until COMMAND prints WANT.
wait_for() {
  local want=$1 got
  shift
  for ((i=0;i<100;i++)); do
    got=$("$@")
    [[ $got != "$want" ]] || return 0
    sleep 0.1
  done
  echo "$*: expected $want, got $got" >&2
  herdr plugin log list | jq -r '.result.logs[] | select(.plugin_id == "worktree" and .status == "failed") | .stderr' | tail -n 5 >&2
  exit 1
}
settle() {
  wait_for 0 bash -c 'herdr plugin log list | jq "[.result.logs[] | select(.plugin_id == \"worktree\" and .status == \"running\")] | length"'
}

# app: its shell, an agent in the main checkout, a shell cd'd into the worktree, and an agent
# started there.
app=$(herdr workspace create --cwd "$scratch/app" --label app | jq -er '.result.workspace.workspace_id')
shell=$(herdr pane list --workspace "$app" | jq -er '.result.panes[0].pane_id')
main_agent=$(herdr pane split "$shell" --direction right --cwd "$scratch/app" | jq -er '.result.pane.pane_id')
side_shell=$(herdr pane split "$shell" --direction down --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
side_agent=$(herdr pane split "$main_agent" --direction down --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
agent_state "$main_agent"
before=$(focused)
agent_state "$side_agent"

# The worktree's agent gets a space of its own, holding only it.
opened() { [[ -n $(side_space) ]] && echo yes || echo no; }
wait_for yes opened
side=$(side_space)
wait_for "$side" space_of_pane "$side_agent"
settle
[[ $(panes_in "$side") == 1 ]] || { echo "worktree space: expected 1 pane, got $(panes_in "$side")" >&2; exit 1; }
[[ $(space_of_pane "$main_agent") == "$app" ]] || { echo 'the main checkout agent moved' >&2; exit 1; }
[[ $(space_of_pane "$side_shell") == "$app" ]] || { echo 'the shell in the worktree folder moved' >&2; exit 1; }
[[ $(focused) == "$before" ]] || { echo "an agent without the focus took it: $before to $(focused)" >&2; exit 1; }

# A second agent started there, with the focus and zoomed, joins the open space in a tab of
# its own, and the view goes with it. herdr won't move a pane out of a zoomed tab by itself.
second=$(herdr pane split "$shell" --direction right --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
jq -cn --arg pane "$second" '{id: "test", method: "pane.focus", params: {pane_id: $pane}}' |
  /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
herdr pane zoom "$second" --on >/dev/null
agent_state "$second"
wait_for "$side" space_of_pane "$second"
wait_for 2 tabs_in "$side"
# A moved pane takes an id in its new space; herdr still answers to the old one.
wait_for "$(herdr pane get "$second" | jq -r '.result.pane.pane_id')" focused

settle
herdr plugin log list | jq -e 'all(.result.logs[] | select(.plugin_id == "worktree"); .status == "succeeded")' >/dev/null ||
  { herdr plugin log list | jq -c 'first(.result.logs[] | select(.plugin_id == "worktree" and .status != "succeeded"))' >&2; exit 1; }
printf '%s\n' 'worktree adoption passed: an agent in a worktree folder gets its space, a second joins it from a zoomed tab with the view, shells and main-checkout agents stay'
