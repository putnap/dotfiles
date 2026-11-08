#!/usr/bin/env bash
# The popup prefix+< opens: a pane's Claude session name, filled in to edit as herdr's own
# rename dialog does, then typed into the session as its /rename, which the pane's title
# follows. Saved empty, Claude names it from the conversation; unchanged or esc, nothing is sent.
#
# Usage: RENAME_PANE=w1:p2 rename-session.sh   in the popup open-rename.sh opens
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
pane=${RENAME_PANE:?the pane whose session to rename}
# herdr's own dialog colours: background, field, save button, text.
dialog_bg='#171722' field_bg='#2b2c3d' save_bg='#71adff' text='#cdd6f4'

main() {
  ready_for_rename
  current=$(pane_field terminal_title_stripped)
  name=$(ask_name "$current") || exit 0
  if [[ -n $name && $name == "$current" ]]; then exit 0; fi
  # Asked again: the session may have started a turn while the name was typed.
  ready_for_rename
  "$herdr" pane run "$pane" "$(rename_command "$name")" >/dev/null
}

# Only a Claude session waiting at its prompt: typed while it works or asks, the text would
# queue as a message or answer the question.
ready_for_rename() {
  local agent status
  agent=$(pane_field agent)
  status=$(pane_field agent_status)
  if [[ $agent != claude ]]; then die "this pane runs no Claude session"; fi
  case $status in
    idle | done) ;;
    *) die "Claude is $status; rename it once it waits for you" ;;
  esac
}

# fzf as one editable field: esc cancels, ctrl-c clears, and with nothing to pick, enter ends
# on fzf's no-match 1 and prints the field.
ask_name() {
  local typed
  typed=$(fzf --print-query --query="$1" --prompt=' ' --layout=reverse --info=hidden \
      --no-separator --no-scrollbar --input-border=top --bind=ctrl-c:clear-query --header="$(buttons)" \
      --color="bg:$dialog_bg,input-bg:$field_bg,input-border:$field_bg,fg:$text,query:$text:regular,prompt:$text,header:$text" </dev/null) ||
    [[ $? -eq 1 ]] || return 1
  sed -n 1p <<<"$typed"
}

# herdr's three buttons, centred under the field. fzf draws its header two columns in, past
# the pointer and marker, so the padding leaves those out.
buttons() {
  local row visible columns
  row="$(button "$save_bg" "$dialog_bg" '↵save')  $(button "$field_bg" "$text" '^c clear')  $(button "$field_bg" "$text" 'esc cancel')"
  visible=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$row")
  columns=$(stty size </dev/tty | cut -d' ' -f2)
  printf "%*s%s" $(((columns - ${#visible}) / 2 - 2)) "" "$row"
}

button() {
  printf '\e[48;2;%sm\e[38;2;%sm %s \e[0m' "$(rgb "$1")" "$(rgb "$2")" "$3"
}

rgb() {
  printf '%d;%d;%d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"
}

rename_command() {
  if [[ -z $1 ]]; then printf '/rename'; else printf '/rename %s' "$1"; fi
}

pane_field() {
  "$herdr" pane get "$pane" | jq -r --arg field "$1" '.result.pane[$field] // empty'
}

die() {
  printf '\nrename: %s\n' "$*" >&2
  # Held long enough to read, closed by any key, and never forever.
  read -r -s -n 1 -t 30 -p 'press any key to close ' _ || true
  exit 1
}

main
