#!/usr/bin/env bash
# Create a git worktree as a herdr workspace, from the repo the focused pane is in.
#
#   keybinding (popup): new-worktree.sh, an fzf dialog of branches
#   agents:             new-worktree.sh --branch feat/x [--base main] [--no-focus]
#
# A new branch starts from the main checkout's HEAD in a sibling folder, the way
# `git worktree add ../js-x -b feature/eng-1-x` always did; an existing one is checked out.
# From the dialog the worktree also gets a session: a new one of the default agent, or a
# fork of the agent it was opened from, its branch named after that agent's title.
# layout.sh starts that session, on the worktree.created event, as the new space's one pane.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
here=$(dirname "$0")
# Sessions waiting for layout.sh, one file per checkout path. A plugin pane gets
# HERDR_PLUGIN_STATE_DIR; a direct run uses the same folder herdr gives this plugin.
waiting="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/worktree}/waiting"
carry_line="↪ carry this conversation over"

branch="" base="" path="" focus="--focus"
while [ $# -gt 0 ]; do
  case $1 in
    --branch) branch=${2:?--branch needs a value}; shift 2 ;;
    --base) base=${2:?--base needs a value}; shift 2 ;;
    --path) path=${2:?--path needs a value}; shift 2 ;;
    --focus | --no-focus) focus=$1; shift ;;
    *) echo "new-worktree: unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() {
  printf '\nnew-worktree: %s\n' "$*" >&2
  # Hold the popup open long enough to read the error, but never block forever.
  [ -t 0 ] && read -r -s -n 1 -t 30 -p 'press any key to close ' _ || true
  exit 1
}

# An agent runs inside its own pane and gets HERDR_PANE_ID; the popup is not a
# pane, so it falls back to whichever pane the UI has focused.
if [ -n "${HERDR_PANE_ID:-}" ]; then
  pane=$("$herdr" pane get "$HERDR_PANE_ID")
else
  pane=$("$herdr" pane current)
fi
cwd=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$pane")
# open-overlay.sh names the pane the dialog was opened from, since the focus may move meanwhile.
origin=${WORKTREE_ORIGIN_PANE:-${HERDR_PANE_ID:-}}

# --git-common-dir resolves to the *main* repo's .git even from inside a linked
# worktree; --show-toplevel would give the worktree itself, and herdr rejects
# creating from one (linked_worktree_source).
common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  die "$cwd is not a git repository"
repo=$(dirname "$common")

# Create from the repo's parent workspace when it is open; otherwise let herdr
# resolve it from the repo root.
workspace=$("$herdr" workspace list |
  jq -r --arg repo "$repo" 'first(.result.workspaces[]
    | select(.worktree.repo_root == $repo and .worktree.is_linked_worktree == false)
    | .workspace_id) // empty')

# One fzf dialog: search the branches no worktree has checked out, or type a new name.
# enter adds a new session of the default agent, alt-enter only a shell. The first line,
# when there is an agent to carry over, forks its conversation instead. Prints the branch,
# then the session command. fzf's 1 is only no match, a new name; esc closes the dialog at once.
# The preview shows what the line makes: the carried conversation, or a branch's commits.
pick() {
  local fork picked key choice query
  fork=$(fork_command)
  picked=$(dialog_lines "$fork" |
    CARRY_SUMMARY=$(carry_summary "$fork") \
    fzf --print-query --expect=alt-enter --exact --no-multi --height=100% \
        --prompt="worktree in $(basename "$repo")> " \
        --header="enter: new $(default_agent) session · alt-enter: shell only · a new name makes a branch" \
        --preview='if [ {n} = 0 ] && [ -n "$CARRY_SUMMARY" ]; then printf "%s\n" "$CARRY_SUMMARY"; else git -C '"$repo"' log --oneline -12 {} -- 2>/dev/null; fi' \
        --preview-window=right:55%) || [ $? -eq 1 ] || exit 1
  query=$(sed -n 1p <<<"$picked")
  key=$(sed -n 2p <<<"$picked")
  choice=$(sed -n 3p <<<"$picked")
  if [ "$choice" = "$carry_line" ]; then
    printf '%s\n%s\n' "$(branch_from_title "$(carried_title)")" "$fork"
  elif [ "$key" = alt-enter ]; then
    printf '%s\n\n' "${choice:-$query}"
  else
    printf '%s\n%s\n' "${choice:-$query}" "$(agent_command)"
  fi
}

dialog_lines() {
  [ -z "$1" ] || printf '%s\n' "$carry_line"
  branch_candidates
}

# Local first, then remote-only ones with their remote stripped -- checking out
# origin/feat/x means a local feat/x tracking it. git checks a branch out only once,
# so those a worktree already holds are left out.
branch_candidates() {
  {
    git -C "$repo" for-each-ref --format='%(refname:short)' --sort=-committerdate refs/heads
    git -C "$repo" for-each-ref --format='%(refname:lstrip=3)' --sort=-committerdate \
      --exclude='refs/remotes/*/HEAD' refs/remotes
  } | awk '!seen[$0]++' |
    grep -vxF -f <(git -C "$repo" worktree list --porcelain | sed -n 's|^branch refs/heads/||p') || true
}

# The command agent-fork.sh would run for the origin pane's agent, or nothing without one.
fork_command() {
  [ -n "$origin" ] || return 0
  HERDR_PANE_ID=$origin bash "$here/../../../scripts/agent-fork.sh" pane --print-command 2>/dev/null || true
}

# The carry line's preview: the conversation, and the branch and start point it gets.
carry_summary() {
  local title
  [ -n "$1" ] || return 0
  title=$(carried_title)
  printf 'Fork this conversation into a new worktree:\n\n  %s\n\nbranch  %s\nfrom    %s · %s\n' \
    "$title" "$(branch_from_title "$title")" \
    "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" "$(git -C "$repo" log -1 --format='%h %s')"
}

carried_title() {
  [ -n "$origin" ] || return 0
  "$herdr" pane get "$origin" | jq -r '.result.pane.terminal_title_stripped // empty'
}

# "Sync design analysis and principles" -> feature/sync-design-analysis-and-principles
branch_from_title() {
  local slug
  slug=$(tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48 | sed -E 's/-+$//')
  [ -z "$slug" ] || printf 'feature/%s' "$slug"
}

default_agent() {
  dasel -i toml -o json <"$here/../../../plugins/config/agents/config.toml" | jq -r '.default_agent'
}

# The default agent started the way the agents plugin's own entrypoint starts it.
agent_command() {
  dasel -i toml -o json <"$here/../../agents/herdr-plugin.toml" |
    jq -r --arg agent "$(default_agent)" '.panes[] | select(.id == $agent) | .command | map(@sh) | join(" ")'
}

start=""
if [ -z "$branch" ]; then
  choice=$(pick) || exit 1
  # A shell-only pick has no session line left once $(...) drops trailing newlines.
  { read -r branch; read -r start || start=""; } <<<"$choice"
  [ -n "$branch" ] || die "no branch given"
  printf '\n  Creating worktree %s…\n' "$branch"
fi

# Follow the convention the repo already uses rather than herdr's
# ~/.herdr/worktrees default: where do this repo's existing worktrees live?
# pickitoo keeps siblings (js-oncall-console), auto-kaip-sau uses
# .claude/worktrees. Presence of a .claude/worktrees directory is not a usable
# signal -- it exists in repos where an agent ran once, not where you want them.
default_path() {
  slug=${1##*/}
  parent=$(
    git -C "$repo" worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2 |
      while read -r checkout; do dirname "$checkout"; done |
      sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9][0-9]* //'
  )
  [ -n "$parent" ] || parent=$(dirname "$repo")
  if [ "$parent" = "$(dirname "$repo")" ]; then
    printf '%s/%s-%s' "$parent" "$(basename "$repo")" "$slug"
  else
    printf '%s/%s' "$parent" "$slug"
  fi
}

# A branch that exists only on a remote should track it rather than prompt.
if [ -z "$base" ] && ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  remote_ref=$(git -C "$repo" for-each-ref --format='%(refname:short)' \
    --count=1 "refs/remotes/*/$branch")
  [ -n "$remote_ref" ] && base=$remote_ref
fi

# Applied for agents too -- otherwise a caller without --path silently falls
# back to herdr's ~/.herdr/worktrees default.
path=${path:-$(default_path "$branch")}

# Left for layout.sh, which starts it in the new workspace's one pane.
if [ -n "$start" ]; then
  mkdir -p "$waiting"
  printf '%s\n' "$start" >"$waiting/${path//\//_}"
fi

args=(--branch "$branch" "$focus")
if [ -n "$workspace" ]; then args+=(--workspace "$workspace"); else args+=(--cwd "$repo"); fi
[ -n "$base" ] && args+=(--base "$base")
[ -n "$path" ] && args+=(--path "$path")
"$herdr" worktree create "${args[@]}" >/dev/null || { rm -f "$waiting/${path//\//_}"; die "herdr worktree create failed"; }
