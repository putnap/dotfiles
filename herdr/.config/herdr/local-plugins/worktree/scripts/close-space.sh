#!/usr/bin/env bash
# The dialog prefix+x opens on a space's last pane, in place of herdr's own "Close workspace?".
# Enter on the first line closes the space; in a git worktree's space the other lines also
# remove the worktree, then its local branch, then its remote one. Esc closes nothing.
# A merged pull request puts the full cleanup first; an open one gets no remote line, since
# deleting its branch would close it. Changed files and commits not on the main checkout's
# branch are named on the lines that would delete them. A removed worktree leaves a line in
# done.jsonl, which the Herdr app's done shelf lists.
#
# Usage: CLOSE_WORKSPACE=w1 close-space.sh   in the popup close-pane.sh opens
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
workspace=${CLOSE_WORKSPACE:?the space to close}

main() {
  read_space
  read_branch
  choice=$(choices | fzf --layout=reverse --no-multi --no-info --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
    --header="$(header)" --prompt='close> ') || exit 0
  printf '\n  Closing %s…\n' "$label"
  act "$choice"
  focus_main_space
}

# label, and for a linked worktree its checkout and repository.
read_space() {
  local space
  space=$("$herdr" workspace get "$workspace" | jq -c '.result.workspace')
  label=$(jq -r '.label' <<< "$space")
  checkout=$(jq -r 'select(.worktree.is_linked_worktree == true) | .worktree.checkout_path' <<< "$space")
  repo=$(jq -r 'select(.worktree.is_linked_worktree == true) | .worktree.repo_root' <<< "$space")
}

# The checkout's branch and what deleting it would lose; nothing outside a worktree.
read_branch() {
  branch="" changed=0 unmerged=0 remote="" remote_branch="" pr_state="" pr_number="" pr_url=""
  if [[ -z $checkout ]]; then return 0; fi
  branch=$(git -C "$checkout" symbolic-ref --short -q HEAD || true)
  changed=$(git -C "$checkout" status --porcelain | grep -c . || true)
  if [[ -z $branch ]]; then return 0; fi
  read_remote_branch
  printf '  Checking the pull request…' >&2
  read -r pr_state pr_number pr_url <<< "$(gh_pull_request)" || true
  printf '\r\033[K' >&2
  if [[ $pr_state != MERGED ]]; then
    unmerged=$(git -C "$repo" rev-list --count "HEAD..$branch")
  fi
}

# The branch's upstream, or the same name on origin; remote_branch stays empty when git
# knows of none.
read_remote_branch() {
  local merge
  remote=$(git -C "$repo" config --get "branch.$branch.remote" || echo origin)
  merge=$(git -C "$repo" config --get "branch.$branch.merge" || echo "refs/heads/$branch")
  if git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/${merge#refs/heads/}"; then
    remote_branch=${merge#refs/heads/}
  fi
}

# "MERGED 12 https://…", "OPEN 12 https://…", or nothing without one (or without gh).
gh_pull_request() {
  (cd "$repo" && gh pr view "$branch" --json state,number,url --jq '"\(.state) \(.number) \(.url)"' 2>/dev/null) || true
}

# Lines of action, tab, what it says.
choices() {
  if [[ -z $checkout ]]; then
    line close "close $label"
  elif [[ $pr_state == MERGED ]]; then
    line remote "remove the worktree, local and remote branch$(changed_note)"
    line local "remove the worktree and local branch$(changed_note)"
    line worktree "remove the worktree$(changed_note)"
    line close "close, keep the worktree and branches"
  else
    line close "close, keep the worktree and branches"
    line worktree "remove the worktree$(changed_note)"
    line local "remove the worktree and local branch$(changed_note)$(unmerged_note)"
    line remote "remove the worktree, local and remote branch$(changed_note)$(unmerged_note)"
  fi | keep_possible
}

# No branch lines for a detached checkout; no remote line without a remote branch, or while
# a pull request is open on it.
keep_possible() {
  local action text
  while IFS=$'\t' read -r action text; do
    if [[ $action == local || $action == remote ]] && [[ -z $branch ]]; then continue; fi
    if [[ $action == remote ]] && [[ -z $remote_branch || $pr_state == OPEN ]]; then continue; fi
    printf '%s\t%s\n' "$action" "$text"
  done
}

line() { printf '%s\t%s\n' "$1" "$2"; }

changed_note() {
  if [[ $changed -gt 0 ]]; then printf ' · deletes %s' "$(counted "$changed" 'changed file')"; fi
}

unmerged_note() {
  if [[ $unmerged -gt 0 ]]; then printf ' · %s not on %s' "$(counted "$unmerged" commit)" "$(main_branch)"; fi
}

counted() {
  if [[ $1 -eq 1 ]]; then printf '1 %s' "$2"; else printf '%s %ss' "$1" "$2"; fi
}

main_branch() {
  git -C "$repo" symbolic-ref --short -q HEAD || echo HEAD
}

header() {
  if [[ -z $checkout ]]; then printf 'Close this space?'; return 0; fi
  printf '%s' "${branch:-detached checkout}"
  case $pr_state in
    MERGED) printf ' · PR #%s merged' "$pr_number" ;;
    OPEN) printf ' · PR #%s open' "$pr_number" ;;
  esac
}

act() {
  case $1 in
    close) "$herdr" workspace close "$workspace" >/dev/null ;;
    worktree) remove_worktree ;;
    local) remove_worktree; delete_local_branch ;;
    remote) remove_worktree; delete_local_branch; delete_remote_branch ;;
  esac
}

# herdr closes the space with the checkout; --force is what lets changed files go. The agents'
# titles are read first, while their panes still exist.
remove_worktree() {
  local force=() titles
  if [[ $changed -gt 0 ]]; then force=(--force); fi
  titles=$(agent_titles)
  "$herdr" worktree remove --workspace "$workspace" "${force[@]}" >/dev/null || die "herdr could not remove the worktree"
  record_done "$titles" || true
}

agent_titles() {
  "$herdr" pane list --workspace "$workspace" |
    jq -c '[.result.panes[] | select(.agent != null) | (.terminal_title_stripped // .label) | select(. != null and . != "")]' ||
    echo '[]'
}

# One line in the log the done shelf reads; the same shape the Herdr app's worktree mod writes.
record_done() {
  local log=${XDG_STATE_HOME:-$HOME/.local/state}/herdr/done.jsonl
  mkdir -p "$(dirname "$log")"
  jq -nc --argjson at "$(($(date +%s) * 1000))" --arg repo "$repo" --arg branch "$branch" --argjson titles "$1" \
    --arg number "$pr_number" --arg url "$pr_url" \
    '{at: $at, repo: $repo, branch: (if $branch == "" then null else $branch end), titles: $titles,
      pull_request: (if $number == "" then null else {number: ($number | tonumber), url: $url} end)}' >> "$log"
}

# -D: a squash-merged branch never counts as merged to git, and the line already named
# any commits it would lose.
delete_local_branch() {
  git -C "$repo" branch -D "$branch" >/dev/null || die "git could not delete $branch"
}

# Already gone when GitHub deleted it on merge; then only the stale remote-tracking ref goes.
delete_remote_branch() {
  local output
  if output=$(git -C "$repo" push "$remote" --delete "$remote_branch" 2>&1); then return 0; fi
  if [[ $output == *"remote ref does not exist"* ]]; then
    git -C "$repo" branch -d -r "$remote/$remote_branch" >/dev/null 2>&1 || true
    return 0
  fi
  die "git could not delete $remote/$remote_branch: $output"
}

focus_main_space() {
  local main
  if [[ -z $repo ]]; then return 0; fi
  main=$("$herdr" workspace list | jq -r --arg repo "$repo" 'first(.result.workspaces[]
    | select(.worktree.repo_root == $repo and .worktree.is_linked_worktree == false) | .workspace_id) // empty')
  if [[ -n $main ]]; then "$herdr" workspace focus "$main" >/dev/null; fi
}

die() {
  printf '\nclose-space: %s\n' "$*" >&2
  # Held long enough to read, closed by any key, and never forever.
  read -r -s -n 1 -t 30 -p 'press any key to close ' _ || true
  exit 1
}

main
