#!/usr/bin/env bash
# Open (adopt) one of this repo's existing git worktrees as a herdr workspace.
#
# Replaces herdr's built-in open_worktree action, which is only offered on a
# parent Git workspace row -- it does nothing when you are already inside a
# worktree child. This resolves the main repo from the focused pane either way.
#
# Runs as `type = "pane"`, not "popup": a popup's stdout is not a tty, so fzf
# renders nothing and hangs. A real pane has a full pty, and fzf opens straight
# into search mode.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

if [ -n "${HERDR_PANE_ID:-}" ]; then
  pane=$("$herdr" pane get "$HERDR_PANE_ID")
else
  pane=$("$herdr" pane current)
fi
cwd=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$pane")

die() { printf '\nopen-worktree: %s\n' "$*" >&2; read -r -t 20 -p 'press enter to close ' _ || true; exit 1; }

# --git-common-dir resolves to the *main* repo's .git even from inside a linked
# worktree, which is what makes this work from a child workspace.
common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  die "$cwd is not a git repository"
repo=$(dirname "$common")

# ● already open in herdr, ○ not yet. Picking an open one just focuses it.
choice=$("$herdr" worktree list --cwd "$repo" |
  jq -r '.result.worktrees[]
         | select(.is_linked_worktree)
         | "\(if .open_workspace_id then "●" else "○" end) \(.branch // "(detached)")\t\(.path)"' |
  fzf --delimiter='\t' --with-nth=1 --no-multi --height=100% \
      --prompt="worktree in $(basename "$repo")> " \
      --preview='git -C {2} log --oneline -12 2>/dev/null' --preview-window=right:55%) ||
  exit 0

path=$(printf '%s' "$choice" | cut -f2)
[ -n "$path" ] || exit 0
"$herdr" worktree open --cwd "$repo" --path "$path" --focus >/dev/null || die "could not open $path"
