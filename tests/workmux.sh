#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
WORKMUX_BIN=${WORKMUX_BIN:-$(command -v workmux || true)}
scratch=$(mktemp -d)
export XDG_STATE_HOME=$scratch/state XDG_CONFIG_HOME=$scratch/config XDG_CACHE_HOME=$scratch/cache
export CODEX_HOME=$scratch/codex
unset HERDR_SOCKET_PATH HERDR_FOOTER_STATE_DIR
mkdir -p "$XDG_CONFIG_HOME/workmux" "$scratch/bin" "$CODEX_HOME/sessions"
cp "$repo/workmux/.config/workmux/defaults.yaml" "$XDG_CONFIG_HOME/workmux/config.yaml"
# Fixtures use live tmux panes but never start a model or send a notification.
cat > "$scratch/bin/workmux" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
SH
chmod +x "$scratch/bin/workmux"
export PATH=$scratch/bin:$PATH
socket=$scratch/tmux.sock
tmux -S "$socket" -f /dev/null new-session -d -x 180 -y 40 -s test 'sleep 300'
export TMUX=$socket,$(tmux -S "$socket" display-message -p '#{pid}'),0
cleanup() {
  result=$?
  if ((result != 0)); then
    [[ ! -f $scratch/restore.log ]] || tail -30 "$scratch/restore.log"
    [[ ! -f $scratch/args.log ]] || cat "$scratch/args.log"
    [[ ! -f $scratch/resurrect/last ]] || cat "$scratch/resurrect/last"
  fi
  tmux -S "$socket" kill-server 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
export TMUX_PANE=$(tmux display-message -p '#{pane_id}')
first=$TMUX_PANE
# Parse the real split bindings and verify the backslash key survives quoting.
sed -n '/^bind .*split-window/p' "$repo/tmux/.config/tmux/tmux.conf" > "$scratch/bindings.conf"
tmux source-file "$scratch/bindings.conf" 2> "$scratch/config-errors"
[[ ! -s $scratch/config-errors ]]
tmux list-keys -T prefix | awk '$4 == "\\\\" && $5 == "split-window" && $6 == "-h" { found = 1 } END { exit !found }'
# Exercise terminal input decoding as well as the configured split commands.
python3 - "$socket" <<'PY'
import os, pty, select, subprocess, sys, time

command = ['tmux', '-S', sys.argv[1]]
def tmux(*args):
    return subprocess.check_output(command + list(args), text=True).strip()

tmux('new-session', '-d', '-s', 'keys', '-x', '120', '-y', '40', 'sleep 300')
master, slave = pty.openpty()
client = subprocess.Popen(command + ['attach-session', '-t', 'keys'],
                          stdin=slave, stdout=slave, stderr=slave,
                          env={**os.environ, 'TERM': 'xterm-256color'})
os.close(slave)
def drain():
    while select.select([master], [], [], 0)[0]:
        os.read(master, 65536)

try:
    for _ in range(100):
        drain()
        if tmux('list-clients', '-t', 'keys'):
            break
        time.sleep(0.02)
    # Shifted characters from Ghostty, plus unshifted keys with explicit Shift.
    for sequence, horizontal in [(b'\x1b[27;6;124~', True), (b'\x1b[27;6;95~', False),
                                 (b'\x1b[124;5u', True), (b'\x1b[95;5u', False),
                                 (b'\x1b[92;6u', True), (b'\x1b[45;6u', False)]:
        original = tmux('display-message', '-p', '-t', 'keys:', '#{pane_id}')
        os.write(master, sequence)
        for _ in range(100):
            drain()
            panes = tmux('list-panes', '-t', 'keys:', '-F', '#{pane_id} #{pane_left} #{pane_top}').splitlines()
            if len(panes) == 2:
                break
            time.sleep(0.02)
        assert len(panes) == 2, (sequence, panes)
        first, second = [line.split() for line in panes]
        assert (first[2] == second[2] and first[1] != second[1]) if horizontal else (
            first[1] == second[1] and first[2] != second[2]), (sequence, panes)
        created = next(line.split()[0] for line in panes if line.split()[0] != original)
        tmux('kill-pane', '-t', created)
    print('tmux split keys passed: terminal encodings and pane geometry')
finally:
    tmux('kill-session', '-t', 'keys')
    client.wait(timeout=5)
    os.close(master)
PY
tmux set-option -g @thm_red '#f38ba8'
second=$(tmux split-window -h -P -F '#{pane_id}' 'sleep 300')
# Both agent providers retain separate identity and footer values.
export HERDR_SOCKET_PATH=/stale/herdr.sock HERDR_PANE_ID=stale
printf '{"session_id":"claude-test"}' | bash "$repo/agents/.config/agent-setup/workmux-hook.sh" claude register
printf '{"session_id":"claude-test","transcript_path":"/does-not-exist","model":{"display_name":"Claude"},"effort":{"level":"high"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":81},"rate_limits":{"five_hour":{"used_percentage":96}}}' |
  bash "$repo/herdr/.config/herdr/footer/claude-cache.sh"
export TMUX_PANE=$second
printf '{"session_id":"codex-test"}' | bash "$repo/agents/.config/agent-setup/workmux-hook.sh" codex register
cat > "$CODEX_HOME/sessions/rollout-codex-test.jsonl" <<'JSON'
{"type":"turn_context","payload":{"model":"Codex","effort":"high","approval_policy":"on-request","sandbox_policy":{"type":"workspace-write"}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12000,"cached_input_tokens":10000,"output_tokens":1000},"last_token_usage":{"total_tokens":20000},"model_context_window":100000}}}
JSON
bash "$repo/herdr/.config/herdr/footer/collect.sh" --tmux --once
unset HERDR_SOCKET_PATH HERDR_PANE_ID
claude=$(tmux show-options -pqv -t "$first" @footer)
codex=$(tmux show-options -pqv -t "$second" @footer)
[[ $claude == *Claude* && $claude == *'ctx 81%'* && $claude == *'5h 96%'* && $claude == *'#f38ba8'* ]]
[[ $codex == *Codex* && $codex == *'spent 3k'* && $codex == *'[workspace]'* ]]
[[ $claude != *Codex* && $codex != *Claude* ]]
[[ $(bash "$repo/tmux/.config/tmux/scripts/agent-fork.sh" resume-command "$second") == 'codex resume codex-test '* ]]
# Saved tmux layouts must resume the exact session, including in the main checkout.
printf 'pane\ttest\t0\t1\t:*\t1\t:test\t:/tmp\t1\tcodex\t:codex\n' > "$scratch/layout"
bash "$repo/tmux/.config/tmux/scripts/workmux.sh" save "$scratch/layout"
[[ $(cut -f11 "$scratch/layout") == ':codex resume codex-test' ]]
# A reused pane must not display the previous occupant's metrics or fork it.
tmux set-option -p -t "$second" @workmux_hook '{"provider":"codex","session":"old","identity":"0 old"}'
bash "$repo/herdr/.config/herdr/footer/collect.sh" --tmux --once
[[ -z $(tmux show-options -pqv -t "$second" @footer) ]]
if bash "$repo/tmux/.config/tmux/scripts/agent-fork.sh" resume-command "$second" >/dev/null 2>&1; then exit 1; fi
# Hook installation preserves other integrations and is repeatable.
printf 'workmux footer and identity integration passed\n'
if [[ -n ${WORKMUX_BIN:-} ]]; then
  export PATH=$(dirname "$WORKMUX_BIN"):$PATH
  export DUMMY_ARGS_LOG=$scratch/args.log
  cat <<'C' | cc -x c - -o "$scratch/bin/codex"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
  FILE *file = fopen(getenv("DUMMY_ARGS_LOG"), "a");
  for (int i = 0; i < argc; i++) fprintf(file, "%s%s", i ? " " : "", argv[i]);
  fprintf(file, "\n");
  fclose(file);
  for (;;) sleep(60);
}
C
  tmux set-environment -g DUMMY_ARGS_LOG "$DUMMY_ARGS_LOG"
  native=$(tmux new-window -d -P -F '#{pane_id}' -n native "$scratch/bin/codex")
  export TMUX_PANE=$native
  for ((attempt=0;attempt<100;attempt++)); do
    [[ $(tmux display-message -p -t "$native" '#{pane_current_command}') != codex ]] || break
    sleep 0.1
  done
  printf '{"session_id":"native-test"}' | bash "$repo/agents/.config/agent-setup/workmux-hook.sh" codex register
  printf '{"session_id":"native-test"}' | bash "$repo/agents/.config/agent-setup/workmux-hook.sh" codex working
  jq -s -e 'any(.[]; .agent_session_id == "native-test" and .status == "working")' "$XDG_STATE_HOME"/workmux/agents/*.json >/dev/null
  before=$(tmux list-panes -a -F '#{@workmux_role}' | rg -c '^sidebar$')
  workmux sidebar --session on
  [[ $(tmux list-panes -a -F '#{@workmux_role}' | rg -c '^sidebar$') == "$before" ]]
  cp "$repo/workmux/.config/workmux/defaults.yaml" "$XDG_CONFIG_HOME/workmux/defaults.yaml"
  tmux set-option -g @thm_fg '#123456'
  tmux set-option -g @thm_surface_0 '#234567'
  bash "$repo/tmux/.config/tmux/scripts/workmux.sh" start
  jq -e '.theme.custom.text == "#123456" and .theme.custom.current_row_bg == "#234567"' "$XDG_CONFIG_HOME/workmux/config.yaml" >/dev/null
  tmux set-option -g @thm_fg '#abcdef'
  bash "$repo/tmux/.config/tmux/scripts/workmux.sh" start
  jq -e '.theme.custom.text == "#abcdef"' "$XDG_CONFIG_HOME/workmux/config.yaml" >/dev/null
  # Use the existing Peon test interface; no sound or desktop banner escapes the fixture.
  export CLAUDE_PEON_DIR=$scratch/peon PEON_TEST=1
  mkdir -p "$CLAUDE_PEON_DIR/scripts"
  ln -s "$HOME/.claude/hooks/peon-ping/packs" "$CLAUDE_PEON_DIR/packs"
  dasel -i toml -o json < "$repo/agents/.config/agent-setup/peon.toml" > "$scratch/preferences"
  jq -s '.[0] * .[1] * {notification_style:"standard",use_sound_effects_device:true,debug:true}' "$HOME/.claude/hooks/peon-ping/config.json" "$scratch/preferences" > "$CLAUDE_PEON_DIR/config.json"
  for name in peon-play notify.sh; do
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\n' "$CLAUDE_PEON_DIR/$name.calls" > "$CLAUDE_PEON_DIR/scripts/$name"
    chmod +x "$CLAUDE_PEON_DIR/scripts/$name"
  done
  for status in done done waiting waiting working done; do
    printf '{"session_id":"native-test","cwd":"/tmp"}' | bash "$repo/agents/.config/agent-setup/workmux-hook.sh" codex "$status"
  done
  for name in peon-play notify.sh; do
    [[ $(wc -l < "$CLAUDE_PEON_DIR/$name.calls" | tr -d ' ') == 3 ]]
  done
  printf 'workmux notifications passed: completion, waiting, duplicate suppression\n'
  # Round-trip a real tmux-resurrect save, using harmless binaries as both agents and Neovim.
  plugin=$HOME/.tmux/plugins/tmux-resurrect
  mkdir -p "$scratch/home/.tmux/plugins" "$scratch/home/.config/tmux"
  ln -s "$plugin" "$scratch/home/.tmux/plugins/tmux-resurrect"
  ln -s "$repo/tmux/.config/tmux/scripts" "$scratch/home/.config/tmux/scripts"
  cp "$scratch/bin/codex" "$scratch/bin/nvim"
  cp "$scratch/bin/codex" "$scratch/bin/claude"
  editor=$(tmux new-window -d -P -F '#{pane_id}' -n editor -c "$scratch" "$scratch/bin/nvim" example.txt)
  for ((attempt=0;attempt<100;attempt++)); do
    [[ $(tmux display-message -p -t "$editor" '#{pane_current_command}') != nvim ]] || break
    sleep 0.1
  done
  [[ $(tmux display-message -p -t "$editor" '#{pane_current_command}') == nvim ]]
  mkdir "$scratch/project"
  git -C "$scratch/project" init -q -b main
  git -C "$scratch/project" -c user.name=Test -c user.email=test@example.invalid commit -qm initial --allow-empty
  (cd "$scratch/project" && workmux add task --base main --name custom --background)
  git -C "$scratch/project" worktree list --porcelain | rg -q '/custom$'
  target=$(tmux list-windows -a -F '#{window_id} #{window_name}' | awk '/custom$/ {print $1}')
  [[ -n $target ]]
  [[ $(tmux list-panes -t "$target" -F '#{@workmux_role}' | rg -cv '^sidebar$') == 2 ]]
  printf 'workmux worktree layout passed\n'
  workmux sidebar on
  tmux set-option -g @resurrect-dir "$scratch/resurrect"
  tmux set-option -g @resurrect-hook-post-save-layout "bash $repo/tmux/.config/tmux/scripts/workmux.sh save"
  bash "$plugin/scripts/save.sh" quiet
  workmux sidebar off
  tmux kill-server
  : > "$DUMMY_ARGS_LOG"
  export HOME=$scratch/home
  unset TMUX TMUX_PANE
  tmux -S "$socket" -f /dev/null new-session -d -x 180 -y 40 -s restore /bin/bash
  export TMUX=$socket,$(tmux -S "$socket" display-message -p '#{pid}'),0
  tmux set-option -g default-shell /bin/bash
  tmux set-option -g default-command '/bin/bash --noprofile --norc'
  tmux set-option -g @resurrect-dir "$scratch/resurrect"
  tmux set-option -g @resurrect-processes '"~nvim->nvim" claude codex "workmux _sidebar-run"'
  tmux set-option -g @resurrect-hook-pre-restore-all 'tmux set-option -g @workmux_restoring on'
  tmux set-option -g @resurrect-hook-post-restore-all "bash $repo/tmux/.config/tmux/scripts/workmux.sh finish-restore"
  tmux set-option -g @resurrect-hook-pre-restore-pane-processes "bash $repo/tmux/.config/tmux/scripts/workmux.sh restore-sidebars"
  bash "$plugin/scripts/restore.sh" > "$scratch/restore.log" 2>&1
  for ((attempt=0;attempt<100;attempt++)); do
    if rg -q 'codex resume native-test' "$DUMMY_ARGS_LOG" && rg -q 'nvim$' "$DUMMY_ARGS_LOG"; then break; fi
    sleep 0.1
  done
  rg -q 'codex resume native-test' "$DUMMY_ARGS_LOG"
  rg -q 'nvim$' "$DUMMY_ARGS_LOG"
  ! rg -q 'example.txt' "$DUMMY_ARGS_LOG"
  sidebars=$(tmux list-panes -a -F '#{@workmux_role}' | rg -c '^sidebar$')
  workmux sidebar on
  [[ $(tmux list-panes -a -F '#{@workmux_role}' | rg -c '^sidebar$') == "$sidebars" ]]
  workmux sidebar off
  printf 'tmux restore passed: exact agent session, Neovim process, sidebar reuse\n'
  printf 'native workmux passed: hooks, sidebar, idempotence, tmux theme changes\n'
fi
