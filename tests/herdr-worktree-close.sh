#!/usr/bin/env bash
# prefix+x through the worktree plugin, on a temporary server with a bare repository as the
# remote: a pane with others beside it closes at once, a space's last opens the close dialog
# as a popup, and the dialog, typed into a pane of its own, removes a merged pull request's
# worktree with its local and remote branch, an open one's with only its local branch, and
# closes a worktree's space while keeping everything, or nothing on esc. gh is a stub.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-close.XXXXXX)
# Resolved, because git reports /tmp checkouts by their real /private/tmp path. Separate from
# mktemp, so its failure stops the script instead of resolving the current directory.
scratch=$(cd "$scratch" && pwd -P)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
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
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view feature/eng-1-merged") echo 'MERGED 1' ;;
  "pr view feature/eng-2-open") echo 'OPEN 2' ;;
  *) echo 'no pull requests found' >&2; exit 1 ;;
esac
STUB
chmod +x "$scratch/bin/gh"

git init -q --bare -b main "$scratch/origin.git"
git init -q -b main "$scratch/app"
git -C "$scratch/app" commit -q --allow-empty -m init
git -C "$scratch/app" remote add origin "$scratch/origin.git"
git -C "$scratch/app" push -q -u origin main

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
app=$(herdr workspace create --cwd "$scratch/app" --label app | jq -er '.result.workspace.workspace_id')

# worktree NAME: a worktree's space with a pushed branch holding one commit; prints the space.
worktree() {
  herdr worktree create --cwd "$scratch/app" --branch "feature/$1" --path "$scratch/app-$1" --no-focus |
    jq -er '.result.workspace.workspace_id'
  git -C "$scratch/app-$1" commit -q --allow-empty -m "$1"
  git -C "$scratch/app-$1" push -q -u origin "feature/$1"
}
merged=$(worktree eng-1-merged)
open=$(worktree eng-2-open)
kept=$(worktree eng-3-kept)
touch "$scratch/app-eng-3-kept/notes.txt"

expect() {
  if [[ $2 != "$1" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$3" "$1" "$2" >&2
    exit 1
  fi
}
# wait_for WANT COMMAND...: removal runs in the dialog's own time.
wait_for() {
  local want=$1 got
  shift
  for ((i=0;i<100;i++)); do
    got=$("$@")
    [[ $got != "$want" ]] || return 0
    sleep 0.1
  done
  echo "$*: expected '$want', got '$got'" >&2
  [[ -z ${dialog_pane:-} ]] || herdr pane read "$dialog_pane" --source recent --lines 20 >&2 || true
  exit 1
}
panes_in() { herdr pane list --workspace "$1" | jq '.result.panes | length'; }
space_open() { herdr workspace list | jq -r --arg id "$1" 'any(.result.workspaces[]; .workspace_id == $id)'; }
exists() { if [[ -e $1 ]]; then echo yes; else echo no; fi; }
local_branch() { if git -C "$scratch/app" show-ref --verify --quiet "refs/heads/$1"; then echo yes; else echo no; fi; }
remote_branch() { if git -C "$scratch/origin.git" show-ref --verify --quiet "refs/heads/$1"; then echo yes; else echo no; fi; }
focus() {
  jq -cn --arg pane "$1" '{id: "test", method: "pane.focus", params: {pane_id: $pane}}' |
    /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
}
only_pane_of() { herdr pane list --workspace "$1" | jq -r '.result.panes[0].pane_id'; }

# prefix+x on a pane with another beside it closes just that pane.
extra=$(herdr pane split "$(only_pane_of "$open")" --direction right --cwd "$scratch/app-eng-2-open" | jq -er '.result.pane.pane_id')
focus "$extra"
herdr plugin action invoke worktree.close >/dev/null
wait_for 1 panes_in "$open"

# On a space's last pane it opens the dialog as a popup and closes nothing itself.
focus "$(only_pane_of "$open")"
herdr plugin action invoke worktree.close >/dev/null
sleep 1
expect 1 "$(panes_in "$open")" 'the last pane stays until the dialog answers'

# [shows=TEXT] dialog SPACE KEYS...: the dialog for SPACE in a fresh pane of the app space,
# once it shows TEXT, then the keys.
dialog() {
  local space=$1
  shift
  dialog_pane=$(herdr pane split "$(only_pane_of "$app")" --direction down --cwd "$scratch/app" | jq -er '.result.pane.pane_id')
  herdr pane run "$dialog_pane" "PATH=$scratch/bin:\$PATH CLOSE_WORKSPACE=$space bash $repo/herdr/.config/herdr/local-plugins/worktree/scripts/close-space.sh; echo dialog-closed-\$?" >/dev/null
  herdr pane wait-output "$dialog_pane" --match "${shows:-close>}" --timeout 10000 >/dev/null ||
    { echo "the dialog for $space does not show '${shows:-close>}'" >&2; herdr pane read "$dialog_pane" --source recent --lines 20 >&2; exit 1; }
  for key in "$@"; do herdr pane send-keys "$dialog_pane" "$key" >/dev/null; done
  herdr pane wait-output "$dialog_pane" --regex 'dialog-closed-[0-9]' --timeout 10000 >/dev/null ||
    { echo "the dialog for $space did not finish" >&2; herdr pane read "$dialog_pane" --source recent --lines 20 >&2; exit 1; }
  herdr pane close "$dialog_pane" >/dev/null
}

# A merged pull request: the first line removes the worktree, local and remote branch.
dialog "$merged" enter
wait_for false space_open "$merged"
expect no "$(exists "$scratch/app-eng-1-merged")" 'the merged worktree is removed'
expect no "$(local_branch feature/eng-1-merged)" 'the merged local branch is deleted'
expect no "$(remote_branch feature/eng-1-merged)" 'the merged remote branch is deleted'

# An open one has no remote line: close, worktree, local, so the third removes the local branch.
dialog "$open" down down enter
wait_for false space_open "$open"
expect no "$(exists "$scratch/app-eng-2-open")" 'the open worktree is removed'
expect no "$(local_branch feature/eng-2-open)" 'the open local branch is deleted'
expect yes "$(remote_branch feature/eng-2-open)" 'the open pull request keeps its branch'

# Esc closes nothing, and the lines that would delete a changed file say so; the first line
# without a pull request closes the space and keeps the rest.
shows='deletes 1 changed file' dialog "$kept" esc
expect true "$(space_open "$kept")" 'esc keeps the space'
dialog "$kept" enter
wait_for false space_open "$kept"
expect yes "$(exists "$scratch/app-eng-3-kept/notes.txt")" 'closing keeps the worktree and its changes'
expect yes "$(local_branch feature/eng-3-kept)" 'closing keeps the local branch'
expect yes "$(remote_branch feature/eng-3-kept)" 'closing keeps the remote branch'

printf '%s\n' 'worktree close passed: a pane closes at once, the last opens the dialog, merged cleans all, open keeps its remote, close keeps everything, esc nothing'
