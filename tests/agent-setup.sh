#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
home=$scratch/home
mkdir -p "$home/.claude" "$home/.codex"
mkdir -p "$home/.claude/skills/wizard"
printf 'local skill notes' > "$home/.claude/skills/wizard/local-notes.txt"
printf '{"permissions":{"allow":["Bash(pnpm:*)"]},"unknown":42,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-claude-hook"}]}]}}\n' > "$home/.claude/settings.json"
printf 'original agreement' > "$home/.claude/CLAUDE.md"
printf 'sandbox_mode="read-only"\n[projects."/example"]\ntrust_level="trusted"\n' > "$home/.codex/config.toml"
printf '[hooks]\nmanaged_dir="/example/hooks"\n[hooks.state.example]\ntrusted_hash="keep-trust"\n' >> "$home/.codex/config.toml"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-codex-hook"}]}]}}\n' > "$home/.codex/hooks.json"
cp "$home/.claude/settings.json" "$scratch/original"
cp "$home/.codex/config.toml" "$scratch/codex"
bash "$repo/agents/.config/agent-setup/apply.sh" --repo "$repo" --home "$home" --apply > "$scratch/first"
for agent in claude codex; do
  file=$home/.$agent/hooks.json
  [[ $agent != claude ]] || file=$home/.claude/settings.json
  jq -e --arg agent "$agent" '[.hooks.Stop[].hooks[].command] | length == 2 and any(. == ("keep-" + $agent + "-hook")) and any(contains("workmux-hook.sh"))' "$file" >/dev/null
done
jq -e '.permissions.allow == ["Bash(pnpm:*)"] and .unknown == 42' "$home/.claude/settings.json" >/dev/null
dasel -i toml -o json < "$home/.codex/config.toml" | jq -e '.sandbox_mode == "workspace-write" and .projects["/example"].trust_level == "trusted"' >/dev/null
dasel -i toml -o json < "$home/.codex/config.toml" | jq -e '.hooks.state.example.trusted_hash == "keep-trust" and .hooks.managed_dir == "/example/hooks"' >/dev/null
dasel -i toml -o json < "$home/.codex/config.toml" | jq -e '.tui.keymap.global.open_transcript == "ctrl-o" and .tui.keymap.global.copy == "alt-c" and .tui.keymap.composer.submit == ["enter"]' >/dev/null
dasel -i toml -o json < "$home/.codex/config.toml" | jq -e '.tui.status_line == []' >/dev/null
[[ $home/.claude/CLAUDE.md -ef $repo/agents/.agents/AGENTS.md ]]
[[ -L $home/.claude/skills/wizard ]]
bash "$repo/agents/.config/agent-setup/apply.sh" --repo "$repo" --home "$home" --apply > "$scratch/second"
# Codex trusts hooks by position, so workmux and atuin keep their places across applies.
for agent in claude codex; do
  file=$home/.$agent/hooks.json
  [[ $agent != claude ]] || file=$home/.claude/settings.json
  jq -e '[.hooks.PostToolUse[].hooks[].command] | length == 2 and (.[0] | contains("workmux-hook.sh")) and (.[1] | contains("atuin hook"))' "$file" >/dev/null
done
dasel -i toml -o json < "$home/.codex/config.toml" | jq -e '.mcp_servers.atuin.args == ["mcp"]' >/dev/null
[[ $(find "$home/.local/state/agent-setup/backups" -name manifest.json | wc -l | tr -d ' ') == 1 ]]
manifest=$(find "$home/.local/state/agent-setup/backups" -name manifest.json)
bash "$repo/agents/.config/agent-setup/apply.sh" --rollback "$manifest" >/dev/null
cmp "$scratch/original" "$home/.claude/settings.json"
cmp "$scratch/codex" "$home/.codex/config.toml"
[[ $(cat "$home/.claude/CLAUDE.md") == 'original agreement' ]]
[[ $(cat "$home/.claude/skills/wizard/local-notes.txt") == 'local skill notes' ]]
printf '{"tui":{"local":true,"old":1},"hooks":{"Stop":[{"hooks":[{"command":"/x/peon-ping/peon.sh"},{"command":"keep"}]}]}}' > "$scratch/live"
printf '{"tui":{"notifications":false}}' > "$scratch/wanted"
printf '{"test":{"tui":{"old":1}}}' > "$scratch/previous"
jq -n --slurpfile live "$scratch/live" --slurpfile wanted "$scratch/wanted" --slurpfile previous "$scratch/previous" --arg name test --argjson protected '["permissions"]' -f "$repo/agents/.config/agent-setup/merge.jq" |
  jq -e '.tui == {local:true, notifications:false} and .hooks.Stop[0].hooks == [{command:"keep"}]' >/dev/null
printf '{"permissions":{}}' > "$scratch/wanted"
if jq -n --slurpfile live "$scratch/live" --slurpfile wanted "$scratch/wanted" --slurpfile previous "$scratch/previous" --arg name test --argjson protected '["permissions"]' -f "$repo/agents/.config/agent-setup/merge.jq" >/dev/null 2>&1; then echo 'protected setting accepted' >&2; exit 1; fi
printf 'Shell setup tests passed: merge, protection, hooks, Stow, idempotence, rollback.\n'
# Exercise the actual launcher with a fake herdr CLI; no real panes or agents.
cat > "$scratch/herdr" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$1 $2" in
  'pane current') printf '{"result":{"pane":{"pane_id":"p1","cwd":"/tmp/a path"}}}\n';;
  'agent get')
    if [[ ${TEST_INVALID:-false} == true ]]; then jq -cn --arg provider "$TEST_PROVIDER" '{result:{agent:{agent:$provider}}}'
    else jq -cn --arg provider "$TEST_PROVIDER" '{result:{agent:{agent:$provider,agent_session:{agent:$provider,kind:"id",value:"id-123"}}}}'; fi;;
  'pane split'|'tab create') printf '{"result":{"pane":{"pane_id":"p2"}}}\n';;
  'pane process-info') printf '{"result":{"process_info":{"foreground_processes":[{"name":"claude","pid":123}]}}}\n';;
  *) printf '{"result":{}}\n';;
esac
MOCK
chmod +x "$scratch/herdr"
export HERDR_BIN_PATH=$scratch/herdr TEST_CALLS=$scratch/calls CLAUDE_CONFIG_DIR=$scratch/claude
mkdir -p "$CLAUDE_CONFIG_DIR/projects/example"
printf '{"permissionMode":"bypassPermissions"}\n' > "$CLAUDE_CONFIG_DIR/projects/example/id-123.jsonl"
for provider in codex claude; do
  export TEST_PROVIDER=$provider
  : > "$TEST_CALLS"
  bash "$repo/agents/.config/agent-setup/control.sh" fork pane
  if [[ $provider == codex ]]; then grep -q 'pane run p2 codex fork id-123' "$TEST_CALLS"
  else grep -q 'pane run p2 claude --resume id-123 --fork-session --permission-mode bypassPermissions' "$TEST_CALLS"; fi
done
: > "$TEST_CALLS"
export TEST_PROVIDER=codex
if TEST_INVALID=true bash "$repo/agents/.config/agent-setup/control.sh" fork pane >/dev/null 2>&1; then exit 1; fi
! grep -Eq '^(pane split|tab create|pane run)' "$TEST_CALLS"
grep -q '^notification show Agent fork failed' "$TEST_CALLS"
# An already-Stowed herdr package must work before the agents package is applied.
mkdir -p "$scratch/wrapper-home/.config/herdr"
ln -s "$repo/herdr/.config/herdr/scripts" "$scratch/wrapper-home/.config/herdr/scripts"
HOME=$scratch/wrapper-home bash "$scratch/wrapper-home/.config/herdr/scripts/agent-fork.sh" pane --print-command | grep -q 'codex fork id-123'
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
printf '{"sessionId":"id-123"}\n' > "$CLAUDE_CONFIG_DIR/sessions/123.json"
TEST_PROVIDER=claude TEST_INVALID=true bash "$repo/agents/.config/agent-setup/control.sh" fork pane --print-command |
  grep -q 'claude --resume id-123 --fork-session --permission-mode bypassPermissions'
export HERDR_PLUGIN_CONFIG_DIR=$repo/herdr/.config/herdr/plugins/config/agents
export HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_cwd":"/tmp/a path","focused_pane_id":"p1"}'
bash "$repo/agents/.config/agent-setup/control.sh" launch split
grep -q -- '--entrypoint claude --placement split --focus --cwd /tmp/a path --target-pane p1 --direction right' "$TEST_CALLS"
echo 'Launcher tests passed: configured provider, cwd, exact forks, invalid identity creates no pane.'
# Declared GitHub plugins, through a fake herdr in a home that counts as the real one.
plugin_home=$scratch/plugin-home
mkdir -p "$plugin_home/.config/herdr" "$scratch/bin"
printf '{"mcpServers":{"atuin":{}}}\n' > "$plugin_home/.claude.json"
printf '[{"plugin_id":"devswha.ovis","source":{"kind":"github","owner":"devswha","repo":"ovis"}}]\n' > "$plugin_home/.config/herdr/plugins.json"
cat > "$scratch/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$1" in
  status) printf '{"server":{"running":false}}\n';;
  integration) printf 'claude: installed\ncodex: installed\n';;
esac
MOCK
chmod +x "$scratch/bin/herdr"
cat > "$scratch/bin/claude" <<'MOCK'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  --version) echo '9.9.9 (Claude Code)';;
  'plugin install tokeneconomizer@tokeneconomizer')
    mkdir -p "$HOME/te/scripts"
    printf '#!/usr/bin/env bash\nprintf "te %%s\\n" "$*" >> "$TEST_CALLS"\n' > "$HOME/te/scripts/te"
    chmod +x "$HOME/te/scripts/te"
    mkdir -p "$HOME/.claude/plugins"
    jq -n --arg path "$HOME/te" '{plugins:{"tokeneconomizer@tokeneconomizer":[{installPath:$path}]}}' > "$HOME/.claude/plugins/installed_plugins.json";;
esac
MOCK
chmod +x "$scratch/bin/claude"
: > "$TEST_CALLS"
HOME=$plugin_home PATH=$scratch/bin:$PATH bash "$repo/agents/.config/agent-setup/apply.sh" --repo "$repo" --home "$plugin_home" --apply --integrations >/dev/null
grep -qx 'plugin install kryptamine/herdr-auto-title --yes' "$TEST_CALLS"
if grep -q 'plugin install devswha/ovis' "$TEST_CALLS"; then echo 'installed plugin reinstalled' >&2; exit 1; fi
grep -qx 'claude plugin marketplace add microsoft/TokenEconomizer' "$TEST_CALLS"
grep -qx 'claude plugin install tokeneconomizer@tokeneconomizer' "$TEST_CALLS"
grep -qx 'te --host claude toolprune refresh-catalog' "$TEST_CALLS"
grep -qx 'te config set toolprune=propose --global' "$TEST_CALLS"
grep -qx "te config set toolprune=off --cwd $repo" "$TEST_CALLS"
mkdir -p "$plugin_home/.tokeneconomizer/hosts/claude"
printf '{"claude_code_version":"9.9.9"}\n' > "$plugin_home/.tokeneconomizer/hosts/claude/catalog.json"
: > "$TEST_CALLS"
HOME=$plugin_home PATH=$scratch/bin:$PATH bash "$repo/agents/.config/agent-setup/apply.sh" --repo "$repo" --home "$plugin_home" --apply --integrations >/dev/null
if grep -Eq '^(claude plugin|te .*refresh-catalog)' "$TEST_CALLS"; then echo 'TokenEconomizer reinstalled or refreshed' >&2; exit 1; fi
echo 'Plugin tests passed: missing GitHub plugins install, installed ones are skipped.'
echo 'TokenEconomizer tests passed: installs once, only proposes pruning (off in dotfiles), refreshes its catalog only on a new Claude version.'
