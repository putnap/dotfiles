# Sourced by report.sh and navigate.sh: tree SNAPSHOT prints the sidebar's tree (tree.jq), and
# send_tokens sends the rows report.sh draws from it.
# jq's search path for the tree module.
scripts_dir=$(dirname "${BASH_SOURCE[0]}")
checkouts_file=${HERDR_PLUGIN_STATE_DIR:?}/checkouts.json
# Both shift+up/down presses as report.sh planned them on its last redraw, for navigate.sh.
plans_file=$HERDR_PLUGIN_STATE_DIR/plans.json

tree() {
  jq -L "$scripts_dir" --argjson checkouts "$(checkouts_of "$1")" 'include "tree"; tree($checkouts)' <<< "$1"
}

# {folder: checkout}, git's own spelling of each path, so a space's worktree and its panes'
# folders compare equal. git costs a process a folder and this runs on every focus change, so a
# folder's checkout is kept once found, until report.sh's next full run forgets them all.
checkouts_of() {
  local known new
  known=$(known_checkouts)
  new=$(new_folders "$1" "$known")
  if [[ -n $new ]]; then known=$(ask_git_for_checkouts <<< "$new" | keep_checkouts "$known"); fi
  printf '%s' "$known"
}

forget_checkouts() {
  rm -f "$checkouts_file"
}

# A failed read, not a check first: a full run can forget them in between. Read in bash, as
# this runs on every focus change.
known_checkouts() {
  local known=""
  if [[ -f $checkouts_file ]]; then known=$(<"$checkouts_file") || true; fi
  if [[ -z $known ]]; then known='{}'; fi
  printf '%s' "$known"
}

new_folders() {
  jq -r -L "$scripts_dir" --argjson known "$2" 'include "tree"; new_folders($known)[]' <<< "$1"
}

# learn_checkouts FOLDERS: asks git about folders, a JSON list, and keeps the answers.
learn_checkouts() {
  jq -r '.[]' <<< "$1" | ask_git_for_checkouts | keep_checkouts "$(known_checkouts)" >/dev/null
}

ask_git_for_checkouts() {
  local folder
  while IFS= read -r folder; do
    printf '%s\t%s\n' "$folder" "$(git -C "$folder" rev-parse --show-toplevel 2>/dev/null || true)"
  done | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

# Reads the folders found; prints them with KNOWN. Written aside and moved in, so an overlapping
# run never reads half of it.
keep_checkouts() {
  local all
  all=$(jq -c --argjson known "$1" '$known + .')
  printf '%s' "$all" > "$checkouts_file.$$"
  mv "$checkouts_file.$$" "$checkouts_file"
  printf '%s' "$all"
}

# Taken before the snapshot: herdr drops a space report older than one it already has, so a
# slow run can't put back a marker the focus has since left. Microseconds: a space's requests
# count on from it, and jq's numbers stop being exact past 2^53, about ten times this.
report_sequence() {
  printf '%s' "${EPOCHREALTIME/./}"
}

# request_lines($sequence), for jq: reads {workspace_id: tokens} and gives a line of report
# requests a space, for send_requests. herdr takes 16 tokens a request, so a space's go can span
# several, numbered on from $sequence.
request_defs='
  def request_lines($sequence):
    to_entries[] | .key as $workspace | .value | to_entries
    | [range(0; length; 16) as $at | .[$at:$at + 16] | from_entries] | to_entries
    | map({id: "sidebar:space", method: "workspace.report_metadata",
           params: {workspace_id: $workspace, source: "plugin:sidebar.tree", seq: ($sequence + .key), tokens: .value}}
          | tojson)
    | join("\u001e");'

# send_tokens SEQUENCE: reads {workspace_id: tokens} and reports them.
send_tokens() {
  jq -r --argjson sequence "$1" "$request_defs request_lines(\$sequence)" | send_requests
}

# A line of requests a space, parted by U+001E, which JSON text never holds unescaped. herdr's
# socket answers one request a connection and drops a space's request numbered below one it has,
# so a space's go in order, the spaces side by side.
send_requests() {
  local space pids=() pid
  while IFS= read -r space; do
    send_in_order "$space" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid"; done
}

send_in_order() {
  local requests request
  IFS=$'\x1e' read -ra requests <<< "$1"
  for request in "${requests[@]}"; do send_request "$request"; done
}

# A space can close between the snapshot and its report; the run its closing starts covers
# what is left, so only that error is let through.
send_request() {
  local answer
  answer=$(printf '%s\n' "$1" | /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1)
  if [[ $answer != *'"result":'* && $answer != *'_not_found"'* ]]; then
    printf 'sidebar: %s\n' "$answer" >&2
    return 1
  fi
}
