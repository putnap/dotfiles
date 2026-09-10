#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-integration.XXXXXX)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
export AGENT_SETUP_DIR=$repo/agents/.config/agent-setup CLAUDE_PEON_DIR=$scratch/peon PEON_TEST=1
mkdir -p "$CLAUDE_PEON_DIR/scripts"
ln -s "$HOME/.claude/hooks/peon-ping/packs" "$CLAUDE_PEON_DIR/packs"
dasel -i toml -o json < "$AGENT_SETUP_DIR/peon.toml" > "$scratch/preferences"
jq -s '.[0] * .[1] * {notification_style:"standard",use_sound_effects_device:true,debug:true}' "$HOME/.claude/hooks/peon-ping/config.json" "$scratch/preferences" > "$CLAUDE_PEON_DIR/config.json"
for name in peon-play notify.sh; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$CLAUDE_PEON_DIR/$name.calls" > "$CLAUDE_PEON_DIR/scripts/$name"
  chmod +x "$CLAUDE_PEON_DIR/scripts/$name"
  : > "$CLAUDE_PEON_DIR/$name.calls"
done
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
rpc() {
  jq -cn --arg method "$1" --argjson params "$2" '{id:"test",method:$method,params:$params}' |
    /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 |
    jq -e 'if .error then error(.error | tostring) else .result end'
}
for ((i=0;i<100;i++)); do
  [[ ! -S $HERDR_SOCKET_PATH ]] || break
  sleep 0.1
done
rpc ping '{}' >/dev/null
for plugin in peon agents; do herdr plugin link "$repo/herdr/.config/herdr/local-plugins/$plugin" >/dev/null; done
first=$(rpc workspace.create "$(jq -cn --arg cwd "$scratch" '{cwd:$cwd,label:"test"}')" | jq -er '.root_pane.pane_id')
second=$(rpc tab.create "$(jq -cn --arg cwd "$scratch" '{cwd:$cwd,focus:true}')" | jq -er '.root_pane.pane_id')
rpc tab.create "$(jq -cn --arg cwd "$scratch" '{cwd:$cwd,focus:true}')" >/dev/null
report() {
  rpc pane.report_agent "$(jq -cn --arg pane "$1" --arg state "$2" --argjson seq "$3" '{pane_id:$pane,source:"custom:integration",agent:"test-agent",state:$state,seq:$seq}')" >/dev/null
  sleep 0.7
}
report "$first" working 101
report "$second" working 101
report "$first" idle 102
report "$second" idle 102
report "$first" blocked 103
report "$first" blocked 103
sleep 3
for name in peon-play notify.sh; do
  count=$(wc -l < "$CLAUDE_PEON_DIR/$name.calls" | tr -d ' ')
  echo "$name calls: $count"
  if [[ $count != 3 ]]; then rpc plugin.log.list '{"plugin_id":"peon","limit":10}'; exit 1; fi
done
# Old-generation clicks must fail before attempting to change focus.
if bash "$AGENT_SETUP_DIR/focus.sh" "$HERDR_SOCKET_PATH" fake old '[]' > "$scratch/focus.log" 2>&1; then exit 1; fi
grep -q 'previous herdr server' "$scratch/focus.log"
echo 'Isolated herdr passed: two completions, one input request, no duplicate; stale click rejected.'
