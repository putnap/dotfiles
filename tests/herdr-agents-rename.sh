#!/usr/bin/env bash
# prefix+< through the agents plugin, on a temporary server: the action opens the rename
# dialog as a popup, and the dialog, typed into a pane of its own with the session's name filled
# in, sends a new name as /rename NAME and a cleared field as a bare /rename to an idle Claude
# pane, and sends nothing unchanged, on esc, while Claude works, or to a pane without Claude.
# Claude is a read loop reported as claude, titled as a session.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-rename.XXXXXX)
scratch=$(cd "$scratch" && pwd -P)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
cat > "$HERDR_CONFIG_PATH" <<'CONFIG'
[ui.toast]
delivery = "off"
[ui.sound]
enabled = false
[terminal]
default_shell = "/bin/sh"
shell_mode = "non_login"
CONFIG

herdr server > "$scratch/server.log" 2>&1 &
server=$!
cleanup() {
  herdr server stop >/dev/null 2>&1 || kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
for ((i=0;i<100;i++)); do
  [[ ! -S $HERDR_SOCKET_PATH ]] || break
  sleep 0.1
done
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/agents" >/dev/null
space=$(herdr workspace create --cwd "$scratch" --label test | jq -er '.result.workspace.workspace_id')
claude=$(herdr pane list --workspace "$space" | jq -er '.result.panes[0].pane_id')
shell=$(herdr pane split "$claude" --direction right --cwd "$scratch" | jq -er '.result.pane.pane_id')
herdr pane run "$claude" 'printf "\033]0;old name\007"; while IFS= read -r line; do printf "got:[%s]\n" "$line"; done' >/dev/null
seq=100
claude_is() {
  seq=$((seq + 1))
  herdr pane report-agent "$claude" --source custom:test --agent claude --state "$1" --seq "$seq" >/dev/null
}
claude_is idle

expect() {
  if [[ $2 != "$1" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$3" "$1" "$2" >&2
    exit 1
  fi
}
received() { herdr pane read "$claude" --source recent --lines 50 | grep -c '^got:\[' || true; }

# [shows=TEXT] [check=FUNCTION] dialog PANE KEYS...: the dialog for PANE in a fresh pane, once
# it shows TEXT and passes the check, then the keys; text: sends literal text instead of a key.
dialog() {
  local target=$1 key
  shift
  dialog_pane=$(herdr pane split "$shell" --direction down --cwd "$scratch" | jq -er '.result.pane.pane_id')
  herdr pane run "$dialog_pane" "RENAME_PANE=$target bash $repo/herdr/.config/herdr/local-plugins/agents/scripts/rename-session.sh; echo dialog-closed-\$?" >/dev/null
  herdr pane wait-output "$dialog_pane" --match "${shows:-esc cancel}" --source visible --timeout 10000 >/dev/null ||
    { echo "the dialog for $target does not show '${shows:-esc cancel}'" >&2; herdr pane read "$dialog_pane" --source recent --lines 20 >&2; exit 1; }
  ${check:-true}
  for key in "$@"; do
    if [[ $key == text:* ]]; then herdr pane send-text "$dialog_pane" "${key#text:}" >/dev/null
    else herdr pane send-keys "$dialog_pane" "$key" >/dev/null; fi
  done
  herdr pane wait-output "$dialog_pane" --regex 'dialog-closed-[0-9]' --timeout 10000 >/dev/null ||
    { echo "the dialog for $target did not finish" >&2; herdr pane read "$dialog_pane" --source recent --lines 20 >&2; exit 1; }
  herdr pane close "$dialog_pane" >/dev/null
}
# The buttons row has as many columns before ↵save as after esc cancel, give or take one.
buttons_centred() {
  local row before after
  row=$(herdr pane read "$dialog_pane" --source visible --format ansi | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r' | grep -m 1 'esc cancel')
  before=${row%%↵save*}
  after=${row##*esc cancel}
  expect 0 "$(((${#before} - ${#after}) / 2))" "the buttons are centred, ${#before} columns before and ${#after} after"
}
wait_received() {
  herdr pane wait-output "$claude" --match "$1" --timeout 5000 >/dev/null ||
    { echo "Claude never got '$1'" >&2; herdr pane read "$claude" --source recent --lines 20 >&2; exit 1; }
}

# A new name becomes /rename NAME; a cleared field a bare /rename, which Claude names itself.
shows='old name' dialog "$claude" ctrl+c 'text:deploy notes' enter
wait_received 'got:[/rename deploy notes]'
dialog "$claude" ctrl+c enter
wait_received 'got:[/rename]'

# The name saved unchanged, esc, a working Claude and a pane without one send nothing.
check=buttons_centred dialog "$claude" enter
dialog "$claude" esc
claude_is working
shows='Claude is working' dialog "$claude" esc
claude_is idle
shows='runs no Claude session' dialog "$shell" esc
sleep 0.5
expect 2 "$(received)" 'unchanged, esc, a working Claude and a shell got nothing'

# prefix+< opens the dialog as a popup, which adds no pane.
jq -cn --arg pane "$claude" '{id: "test", method: "pane.focus", params: {pane_id: $pane}}' |
  /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
panes_before=$(herdr pane list | jq '.result.panes | length')
herdr plugin action invoke agents.rename >/dev/null
sleep 1
expect "$panes_before" "$(herdr pane list | jq '.result.panes | length')" 'the dialog opened as a popup'
printf '%s\n' 'agents rename passed: a new name, Claude naming itself, nothing unchanged, on esc, while working or without Claude, opens as a popup'
