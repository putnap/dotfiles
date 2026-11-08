#!/usr/bin/env bash
# Gives an agent started in a git worktree's folder that worktree's own space. When one starts
# there from any other space (a shell cd'd into it, a tab opened in it), the worktree opens as
# a space, nested under its repository the way prefix+ctrl+g makes them, and the agent's pane
# moves in: as the one pane of a space opened for it, or into a new tab of one already open. Shells and nvim never move, and an agent's folder is the one it started in,
# not where its commands cd to, so nothing else moves. The view follows a pane that had focus.
#
# Usage: adopt-agents.sh   on pane.agent_detected, the agent the event names; else every agent
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}

main() {
  local snapshot pane folder focused
  snapshot=$("$herdr" api snapshot | jq '.result.snapshot')
  while IFS=$'\t' read -r pane folder focused; do
    adopt "$pane" "$folder" "$focused"
  done < <(agents_to_adopt "$snapshot")
}

# Lines of pane, folder and whether it has the focus: the agent an event names, or at startup
# every agent.
agents_to_adopt() {
  jq -r --arg only "$(jq -r '.data.pane_id // ""' <<< "${HERDR_PLUGIN_EVENT_JSON:-null}")" '
    .focused_pane_id as $focused
    | (.panes | map({(.pane_id): (.foreground_cwd // .cwd // "")}) | add // {}) as $folders
    | .agents[] | select($only == "" or .pane_id == $only)
    | [.pane_id, $folders[.pane_id], (.pane_id == $focused)] | @tsv' <<< "$1"
}

adopt() {
  local pane=$1 folder=$2 focused=$3 checkout repo home
  { IFS= read -r checkout; IFS= read -r repo; } < <(linked_worktree "$folder") || true
  if [[ -z $checkout ]]; then return 0; fi
  home=$(space_of "$checkout")
  if [[ $home == "$(space_holding "$pane")" ]]; then return 0; fi
  if [[ -n $home ]]; then
    move_to_new_tab "$pane" "$home" "$focused"
  else
    open_for "$pane" "$checkout" "$repo" "$focused"
  fi
}

# The checkout and its repository for a folder inside a linked worktree; nothing for a main
# checkout or a folder outside Git.
linked_worktree() {
  local top git_dir common
  if [[ -z $1 ]]; then return 0; fi
  { IFS= read -r top; IFS= read -r git_dir; IFS= read -r common; } < <(
    git -C "$1" rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir 2>/dev/null) || true
  if [[ -n $top && $git_dir != "$common" ]]; then printf '%s\n%s\n' "$top" "$(dirname "$common")"; fi
}

# Asked afresh, not read off the snapshot: adopting an earlier agent may have opened it.
space_of() {
  "$herdr" workspace list |
    jq -r --arg checkout "$1" 'first(.result.workspaces[] | select(.worktree.checkout_path == $checkout) | .workspace_id) // empty'
}

space_holding() {
  "$herdr" pane get "$1" | jq -r '.result.pane.workspace_id'
}

move_to_new_tab() {
  unzoom "$1"
  "$herdr" pane move "$1" --workspace "$2" --new-tab $(focus_flag "$3") | moved
}

# The agent takes the place of the shell a space opens with.
open_for() {
  local pane=$1 checkout=$2 repo=$3 focused=$4 opened root
  opened=$("$herdr" worktree open --cwd "$repo" --path "$checkout")
  root=$(jq -er '.result.root_pane.pane_id' <<< "$opened")
  unzoom "$pane"
  "$herdr" pane move "$pane" --tab "$(jq -er '.result.tab.tab_id' <<< "$opened")" --split right \
    --target-pane "$root" $(focus_flag "$focused") | moved
  "$herdr" pane close "$root" >/dev/null
}

# herdr won't move a pane out of a zoomed tab, and says so only in its answer.
unzoom() {
  "$herdr" pane zoom "$1" --off >/dev/null
}

# Reads pane move's answer: a move herdr declined fails here, with its reason.
moved() {
  local answer
  answer=$(cat)
  if ! jq -e '.result.move_result.changed' >/dev/null <<< "$answer"; then
    echo "adopt-agents: herdr declined the move: $(jq -c '.result.move_result.reason // .error' <<< "$answer")" >&2
    return 1
  fi
}

# Said either way: herdr focuses a moved pane unless told not to.
focus_flag() {
  if [[ $1 == true ]]; then printf -- '--focus'; else printf -- '--no-focus'; fi
}

main
