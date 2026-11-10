#!/usr/bin/env bash
# ctrl+\ ctrl+g: one fzf list of the repo's worktrees and the branches none holds, as herdr's
# new-worktree.sh. A worktree opens (the space on it, else a new one); a branch, or a name no
# branch has, gets a new worktree in a new space. Runs in the popup the keys mod opens, in the
# focused terminal's folder.
set -euo pipefail

main() {
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "$PWD is not in a git repository"
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  repo=${common%/.git}
  choice=$(pick) || exit 0
  kind=${choice%%$'\t'*}
  value=${choice#*$'\t'}
  if [ "$kind" = worktree ]; then open_checkout "$value"; else new_checkout "$value"; fi
}

die() {
  printf '\nworktree: %s\n' "$*" >&2
  # Hold the popup open long enough to read the error, but never block forever.
  read -r -s -n 1 -t 30 -p 'press any key to close ' _ || true
  exit 1
}

# Prints "worktree<TAB>path" or "branch<TAB>name"; fails when nothing was chosen. fzf's 1 is
# only no match, so the typed text names a new branch; esc (130) chooses nothing.
pick() {
  local picked query line
  picked=$(rows | fzf --print-query --exact --no-multi --height=100% \
    --delimiter='\t' --with-nth=3 \
    --prompt="worktree in $(basename "$repo")> " \
    --header='enter: open, or a new worktree · a new name makes a branch' \
    --preview="if [ {1} = worktree ]; then git -C {2} log --oneline -12; else git -C $(printf %q "$repo") log --oneline -12 {2} --; fi" \
    --preview-window=right:55%) || [ $? -eq 1 ] || return 1
  query=$(sed -n 1p <<<"$picked")
  line=$(sed -n 2p <<<"$picked")
  if [ -n "$line" ]; then
    cut -f1,2 <<<"$line"
  elif [ -n "$query" ]; then
    printf 'branch\t%s\n' "$query"
  else
    return 1
  fi
}

# kind<TAB>value<TAB>what fzf shows: the worktrees (main first), then the branches.
rows() {
  checkouts | while IFS=$'\t' read -r path branch; do
    printf 'worktree\t%s\t⑂ %s  %s\n' "$path" "$branch" "${path/#$HOME/\~}"
  done
  free_branches | while read -r branch; do
    printf 'branch\t%s\t  %s\n' "$branch" "$branch"
  done
}

# path<TAB>branch of every checkout git still has, the main one first.
checkouts() {
  git -C "$repo" worktree list --porcelain | awk '
    /^worktree / { path = substr($0, 10); branch = "(detached)" }
    /^branch /   { branch = substr($0, 19) }
    /^(bare|prunable)/ { path = "" }
    /^$/ { if (path != "") print path "\t" branch; path = "" }
    END  { if (path != "") print path "\t" branch }'
}

# Local first, then remote-only ones with their remote stripped, each newest first. git checks
# a branch out only once, so those a worktree holds are left out.
free_branches() {
  {
    git -C "$repo" for-each-ref --format='%(refname:short)' --sort=-committerdate refs/heads
    git -C "$repo" for-each-ref --format='%(refname:lstrip=3)' --sort=-committerdate refs/remotes | grep -vx HEAD
  } | awk '!seen[$0]++' | grep -vxF -f <(checkouts | cut -f2) || true
}

open_checkout() {
  local id
  id=$(spaces_on "$1")
  id=${id%%$'\n'*}
  if [ -n "$id" ]; then
    herdr-app do space.select --id "$id" >/dev/null
  else
    herdr-app do space.new --folder "$1" >/dev/null
  fi
}

# The spaces whose first terminal is in this checkout, and not in one nested inside it.
spaces_on() {
  space_places | while IFS=$'\t' read -r id place; do
    if [ "$(checkout_of "$place")" = "$1" ]; then printf '%s\n' "$id"; fi
  done
}

# id<TAB>folder of each space on this machine: where its first terminal is, else where it was made.
space_places() {
  herdr-app ls | jq -r --slurpfile core <(hc ls --json) '
    ($core[0].terminals | map({ (.address): .cwd }) | add // {}) as $cwd
    | .spaces[] | select(.machine == null)
    | [.id, ([.tabs[].terminals[].terminal | ($cwd[.] // empty)] | first) // .folder] | @tsv'
}

# The deepest checkout of this repo holding the folder, or nothing.
checkout_of() {
  checkouts | cut -f1 | awk -v at="$1" '
    at == $0 || index(at, $0 "/") == 1 { if (length($0) > length(best)) best = $0 }
    END { print best }'
}

new_checkout() {
  local path
  path=$(checkout_path "$1")
  printf '\n  Creating worktree %s…\n' "$1"
  add_worktree "$1" "$path" || die "git worktree add failed"
  herdr-app do space.new "$(space_args "$path")" >/dev/null || die "herdr-app could not open $path"
}

# In the folder the repo's worktrees mostly are, else beside the main checkout as
# <repo>-<branch's last part>, as herdr's new-worktree.sh decides it.
checkout_path() {
  local name=${1##*/} beside parent
  beside=$(dirname "$repo")
  parent=$(checkouts | tail -n +2 | while IFS=$'\t' read -r path _; do dirname "$path"; done |
    sort | uniq -c | sort -rn | sed -n '1s/^ *[0-9][0-9]* //p')
  parent=${parent:-$beside}
  if [ "$parent" = "$beside" ]; then
    printf '%s/%s-%s\n' "$parent" "$(basename "$repo")" "$name"
  else
    printf '%s/%s\n' "$parent" "$name"
  fi
}

# A branch is checked out as it is, tracks the remote one, or starts from this checkout's HEAD.
add_worktree() {
  local remote
  remote=$(git -C "$repo" for-each-ref --count=1 --format='%(refname:short)' "refs/remotes/*/$1")
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$1"; then
    git -C "$top" worktree add "$2" "$1"
  elif [ -n "$remote" ]; then
    git -C "$top" worktree add --track -b "$1" "$2" "$remote"
  else
    git -C "$top" worktree add -b "$1" "$2" HEAD
  fi
}

# space.new's arguments: the new space's terminal runs the repo's worktree setup (paseo.json's
# worktree.setup) in a login shell for its PATH, then stays a shell; a failed setup stays readable.
space_args() {
  local setup
  setup=$(jq -r '.worktree.setup // empty' "$repo/paseo.json" 2>/dev/null || true)
  if [ -n "$setup" ]; then
    jq -nc --arg folder "$1" --arg setup "$setup" \
      '{folder: $folder, argv: ["/bin/sh", "-c", "exec \"${SHELL:-/bin/zsh}\" -lic \"$1\"", "sh", "\($setup); exec \"$SHELL\" -l"]}'
  else
    jq -nc --arg folder "$1" '{folder: $folder}'
  fi
}

main "$@"
