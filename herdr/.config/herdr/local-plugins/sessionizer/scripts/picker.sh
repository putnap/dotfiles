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
REFRESH_SECONDS=1

herdr="${HERDR_BIN_PATH:-herdr}"
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

tmp=$(mktemp -d)
cleanup() {
  [ -n "${poller:-}" ] && kill "$poller" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

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
  awk -F/ '{ printf "  %s\t%s\t\n", $NF, $0 }' > "$tmp/repos"

# fzf --listen takes actions over a socket; a poller pushes reload so agent
# status stays live. --track keeps the cursor on the same row across reloads.
sock=$tmp/fzf.sock
(
  while sleep "$REFRESH_SECONDS"; do
    [ -S "$sock" ] || continue
    curl -s --unix-socket "$sock" -XPOST http://localhost/ \
      -d "reload(bash $here/rows.sh $tmp/repos)" >/dev/null 2>&1 || exit 0
  done
) &
poller=$!

choice=$(printf '%s\n' "$open_rows" | cat - "$tmp/repos" |
  fzf --delimiter='\t' --with-nth=1 --no-multi --height=100% --track \
      --listen="$sock" \
      --prompt='workspace> ' --header='enter: focus or create' \
      --preview='git -C {2} log --oneline -12 2>/dev/null || ls -la {2}' \
      --preview-window=right:55%) || exit 0

path=$(cut -f2 <<<"$choice")
workspace=$(cut -f3 <<<"$choice")
[ -n "$path" ] || exit 0

if [ -n "$workspace" ]; then
  exec "$herdr" workspace focus "$workspace"
fi
exec "$herdr" workspace create --cwd "$path" --focus
