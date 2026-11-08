#!/usr/bin/env bash
# The new-worktree dialog, typed into a real pane of a temporary server with the worktree
# plugin linked: a new name makes a branch beside the repo with a new default-agent session,
# an existing branch opens with only a shell, and the first line carries the agent the dialog
# was opened from into a new branch named after its title. claude and codex are stubs, and so
# is agent-fork.sh's helper: its session lookup is covered by agent-setup.sh.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-worktree.XXXXXX)
# Resolved, because git reports /tmp checkouts by their real /private/tmp path. Separate from
# mktemp, so its failure stops the script instead of resolving the current directory.
scratch=$(cd "$scratch" && pwd -P)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
export AGENT_SETUP_DIR=$scratch/agent-setup
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
for agent in claude codex; do
  printf '#!/bin/sh\nprintf "%%s %%s %%s\\n" %s "$PWD" "$*" >> "%s/sessions"\n' "$agent" "$scratch" > "$scratch/bin/$agent"
  chmod +x "$scratch/bin/$agent"
done
git init -q -b main "$scratch/app"
git -C "$scratch/app" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$scratch/app" branch feature/eng-1-existing
touch "$scratch/sessions"
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
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/worktree" >/dev/null

# The agent the dialog is opened from: a Claude session with a title.
agent=$(herdr workspace create --cwd "$scratch/app" --label app | jq -er '.result.root_pane.pane_id')
cat > "$scratch/title.sh" <<'TITLE'
printf '\033]2;%s\007' 'Explore sync design'
TITLE
herdr pane run "$agent" "sh $scratch/title.sh" >/dev/null
herdr pane report-agent "$agent" --source custom:test --agent claude --state idle >/dev/null
# Answers only for the pane the dialog names as its origin.
mkdir -p "$AGENT_SETUP_DIR"
cat > "$AGENT_SETUP_DIR/control.sh" <<FAKE
[ "\$1 \$3" = "fork --print-command" ] && [ "\$HERDR_PANE_ID" = "$agent" ] && echo 'claude --resume sess-123 --fork-session'
FAKE

# dialog KEYS...: opens the dialog in a pane of its own, as the overlay would, then types.
dialog() {
  local pane
  pane=$(herdr pane split "$agent" --direction down --cwd "$scratch/app" | jq -er '.result.pane.pane_id')
  last_dialog=$pane
  herdr pane run "$pane" "WORKTREE_ORIGIN_PANE=$agent bash $repo/herdr/.config/herdr/local-plugins/worktree/scripts/new-worktree.sh; echo dialog-closed-\$?" >/dev/null
  herdr pane wait-output "$pane" --match 'worktree in app>' --timeout 10000 >/dev/null
  "$@" "$pane"
}
# type_name NAME KEY PANE
type_name() {
  [[ -z $1 ]] || herdr pane send-text "$3" "$1" >/dev/null
  herdr pane send-keys "$3" "$2" >/dev/null
}
checkout_of() { git -C "$scratch/app" worktree list --porcelain | awk -v ref="refs/heads/$1" '/^worktree /{path=$2} $2==ref{print path}'; }
session_in() { grep -F " $1 " "$scratch/sessions" | cut -d ' ' -f 1,3- || true; }
# wait_for WANT COMMAND...: worktree creation and layout are asynchronous.
wait_for() {
  local want=$1 got
  shift
  for ((i=0;i<150;i++)); do
    got=$("$@")
    [[ $got != "$want" ]] || return 0
    sleep 0.1
  done
  echo "$*: expected '$want', got '$got'" >&2
  herdr pane read "$last_dialog" --source recent --lines 20 >&2 || true
  exit 1
}

# The carry line, selected first, previews the conversation and the branch it would get; esc
# then closes the dialog at once, with no prompt to close it.
preview_then_esc() {
  herdr pane wait-output "$1" --source visible --match 'branch  feature/explore-sync-design' --timeout 3000 >/dev/null ||
    { echo 'the preview is empty' >&2; herdr pane read "$1" --source recent --lines 20 >&2; exit 1; }
  herdr pane send-keys "$1" esc >/dev/null
}
dialog preview_then_esc
herdr pane wait-output "$last_dialog" --regex 'dialog-closed-[0-9]' --timeout 3000 >/dev/null ||
  { echo 'esc did not close the dialog' >&2; herdr pane read "$last_dialog" --source recent --lines 20 >&2; exit 1; }

dialog type_name feature/eng-2-new-thing enter
herdr pane wait-output "$last_dialog" --match 'Creating worktree feature/eng-2-new-thing' --timeout 3000 >/dev/null ||
  { echo 'the dialog shows no progress once a branch is picked' >&2; exit 1; }
wait_for "$scratch/app-eng-2-new-thing" checkout_of feature/eng-2-new-thing
wait_for 'claude ' session_in "$scratch/app-eng-2-new-thing"
# The session is the new space's one pane.
panes_of_checkout() {
  herdr workspace list | jq -r --arg path "$1" '.result.workspaces[] | select(.worktree.checkout_path == $path) | .workspace_id' |
    xargs -I{} herdr pane list --workspace {} | jq '.result.panes | length'
}
[[ $(panes_of_checkout "$scratch/app-eng-2-new-thing") == 1 ]] ||
  { echo "the new worktree's space: expected 1 pane, got $(panes_of_checkout "$scratch/app-eng-2-new-thing")" >&2; exit 1; }
[[ $(git -C "$scratch/app" rev-parse main) == "$(git -C "$scratch/app" rev-parse feature/eng-2-new-thing)" ]] ||
  { echo 'new branch does not start from main' >&2; exit 1; }

dialog type_name existing alt+enter
wait_for "$scratch/app-eng-1-existing" checkout_of feature/eng-1-existing
sleep 1
wait_for '' session_in "$scratch/app-eng-1-existing"

dialog type_name '' enter
wait_for "$scratch/app-explore-sync-design" checkout_of feature/explore-sync-design
wait_for 'claude --resume sess-123 --fork-session' session_in "$scratch/app-explore-sync-design"
# prefix+ctrl+g opens the dialog as a popup over the layout, which adds no pane.
panes_before=$(herdr pane list | jq '.result.panes | length')
herdr plugin action invoke worktree.new >/dev/null
sleep 1
[[ $(herdr pane list | jq '.result.panes | length') == "$panes_before" ]] ||
  { echo 'the dialog opened as a pane, not a popup' >&2; exit 1; }
printf '%s\n' 'worktree dialog passed: new branch with a session, existing branch with a shell, agent carried over, esc closes, opens as a popup'

