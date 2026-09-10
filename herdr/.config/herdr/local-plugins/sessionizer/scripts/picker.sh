#!/usr/bin/env bash
# tms-style workspace picker. Open herdr workspaces first (with live agent
# status), then every git repo under the roots below that is not open yet.
# Enter focuses or creates.
#
# The roots are the old ~/.config/tms/config.toml search_dirs. `-name .git`
# without `-type d` matters: a worktree's .git is a file, and skipping those
# would hide every js-* checkout.
set -euo pipefail

ROOTS=("$HOME/Documents/Projects:3" "$HOME/dotfiles:2")
REFRESH_SECONDS=2

herdr="${HERDR_BIN_PATH:-herdr}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# One query serves both the first render and the open-path filter below.
open_rows=$(bash "$here/open-rows.sh")
open_paths=$(cut -f2 <<<"$open_rows" | sort -u)

# Repos do not change while the picker is open, so scan once and reuse.
for entry in "${ROOTS[@]}"; do
  root=${entry%:*}; depth=${entry##*:}
  [ -d "$root" ] || continue
  find "$root" -mindepth 1 -maxdepth "$depth" -name .git -prune -print 2>/dev/null
done | sed 's:/\.git$::' | sort -u |
  # Two processes rather than a grep per repo; spawning ~25 greps cost more
  # than everything else here combined. The inner grep drops the empty line
  # printf leaves when nothing is open, which would otherwise match every row.
  grep -vxF -f <(printf '%s\n' "$open_paths" | grep -v '^$') |
  # A linked worktree reads as its repo's child, not as a repo of its own: its
  # .git is a file naming the main checkout, so no git process is needed. Sort
  # key 0/1 keeps the worktrees together, ahead of the plain repos.
  while read -r dir; do
    name=${dir##*/}
    if [ -f "$dir/.git" ]; then
      read -r _ gitdir < "$dir/.git"
      case $gitdir in
        */.git/worktrees/*)
          main=${gitdir%%/.git/worktrees/*}
          repo=${main##*/}
          printf '0\t\u2442 %s \u203a %s\t%s\t\n' "$repo" "${name#"$repo"-}" "$dir"
          continue ;;
      esac
    fi
    printf '1\t  %s\t%s\t\n' "$name" "$dir"
  done |
  sort -t$'\t' -k1,1 -k2,2 | cut -f2- > "$tmp/repos"

# every() reloads in fzf itself, so agent status stays live without a socket
# poller. reload-sync swaps the list in one step instead of blanking it first,
# and --id-nth=2 tracks by path: the label field carries the status icon, which
# changes under the cursor and would lose it on every refresh.
choice=$(printf '%s\n' "$open_rows" | cat - "$tmp/repos" |
  fzf --delimiter='\t' --with-nth=1 --id-nth=2 --no-multi --height=100% --track \
      --bind="every($REFRESH_SECONDS):reload-sync(bash $here/rows.sh $tmp/repos)" \
      --prompt='workspace> ' --header='enter: focus or create' \
      --preview='git -C {2} log --oneline -12 2>/dev/null || ls -la {2}' \
      --preview-window=right:55%) || exit 0

path=$(cut -f2 <<<"$choice")
workspace=$(cut -f3 <<<"$choice")
[ -n "$path" ] || exit 0

if [ -n "$workspace" ]; then
  exec "$herdr" workspace focus "$workspace"
fi

# A linked worktree opened as a plain workspace carries no worktree metadata, so
# herdr lists it top-level instead of under its repo. --git-common-dir points at
# the main repo's .git from inside a worktree, and at our own when we are it.
common=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
repo=${common:+$(dirname "$common")}
if [ -n "$repo" ] && [ "$repo" != "$path" ]; then
  exec "$herdr" worktree open --cwd "$repo" --path "$path" --focus
fi
exec "$herdr" workspace create --cwd "$path" --focus
