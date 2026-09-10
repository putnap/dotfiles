#!/usr/bin/env bash
# Create a git worktree as a herdr workspace, from the repo the focused pane is in.
#
#   keybinding (popup): new-worktree.sh
#   agents:             new-worktree.sh --branch feat/x [--base main] [--no-focus]
#
# The nvim-left layout is applied by layout.sh on the worktree.created event,
# so a plain `herdr worktree create` gets it too.
#
# Runs as an overlay plugin pane, which is a normal pane with a real pty, so
# fzf renders here. It does not in a `popup`, whose stdout is not a tty.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

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
  [ -t 0 ] && read -r -t 30 -p 'press enter to close ' _ || true
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

# Existing branches, local first, then remote-only ones with their remote
# stripped -- checking out origin/feat/x means a local feat/x tracking it.
branch_candidates() {
  {
    git -C "$repo" for-each-ref --format='%(refname:short)' --sort=-committerdate refs/heads
    git -C "$repo" for-each-ref --format='%(refname:lstrip=3)' --sort=-committerdate \
      --exclude='refs/remotes/*/HEAD' refs/remotes
  } | awk '!seen[$0]++'
}

if [ -z "$branch" ]; then
  # --print-query so a name that matches nothing is still usable: fzf exits 1
  # and prints just the query, which becomes the new branch.
  picked=$(branch_candidates |
    fzf --print-query --no-multi --height=100% \
        --prompt="branch in $(basename "$repo")> " \
        --preview='git -C '"$repo"' log --oneline -12 {} -- 2>/dev/null' \
        --preview-window=right:55%) || [ $? -eq 1 ] || die "cancelled"
  branch=$(sed -n '2p' <<<"$picked")
  [ -n "$branch" ] || branch=$(sed -n '1p' <<<"$picked")
  [ -n "$branch" ] || die "no branch given"
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

# An existing branch is just checked out, so there is nothing to base it on.
if [ -z "$base" ] && [ -t 1 ] && ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  base=$(
    { echo HEAD; git -C "$repo" for-each-ref --format='%(refname:short)' --sort=-committerdate refs/heads; } |
      fzf --no-multi --height=100% --prompt="base for $branch> " \
          --preview='git -C '"$repo"' log --oneline -12 {}' --preview-window=right:55%
  ) || die "cancelled"
fi

# Applied for agents too, not just the prompt -- otherwise a non-interactive
# caller silently falls back to herdr's ~/.herdr/worktrees default.
if [ -z "$path" ]; then
  suggested=$(default_path "$branch")
  if [ -t 0 ]; then
    read -r -p "Checkout path [$suggested]: " path
  fi
  path=${path:-$suggested}
fi

args=(--branch "$branch" "$focus")
if [ -n "$workspace" ]; then args+=(--workspace "$workspace"); else args+=(--cwd "$repo"); fi
[ -n "$base" ] && args+=(--base "$base")
[ -n "$path" ] && args+=(--path "$path")
"$herdr" worktree create "${args[@]}" >/dev/null || die "herdr worktree create failed"
