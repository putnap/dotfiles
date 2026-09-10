#!/usr/bin/env bash
set -euo pipefail
api() { "${HERDR_BIN_PATH:-herdr}" "$@" | jq -e '.result'; }
fail() {
  printf 'agent: %s\n' "$*" >&2
  "${HERDR_BIN_PATH:-herdr}" notification show 'Agent fork failed' --body "$*" --sound none >/dev/null 2>&1 || true
  exit 1
}
case "${1:-}" in
  launch)
    placement=${2:?expected tab or split}
    case "$placement" in tab|split) ;; *) fail 'invalid placement';; esac
    config=${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/agents}/config.toml
    agent=$(dasel -i toml -o json < "$config" | jq -er '.default_agent')
    if [[ ${3:-} == --choose ]]; then
      agent=$(printf 'codex\nclaude\n' | fzf --prompt='launch> ' --height=100% --no-multi) || exit 0
    fi
    case "$agent" in claude|codex) ;; *) fail "unsupported default agent: $agent";; esac
    context=${HERDR_PLUGIN_CONTEXT_JSON:-null}
    cwd=$(jq -r '.focused_pane_cwd // .workspace_cwd // empty' <<< "$context")
    args=(plugin pane open --plugin agents --entrypoint "$agent" --placement "$placement" --focus)
    [[ -z $cwd ]] || args+=(--cwd "$cwd")
    if [[ $placement == split ]]; then
      pane=$(jq -er '.focused_pane_id' <<< "$context")
      args+=(--target-pane "$pane" --direction right)
    fi
    api "${args[@]}" >/dev/null
    ;;
  fork)
    target=${2:-pane}
    case "$target" in pane|tab) ;; *) fail 'invalid fork target';; esac
    pane=$(api pane current | jq -e '.pane')
    pane_id=$(jq -er '.pane_id' <<< "$pane")
    agent=$(api agent get "$pane_id" | jq -e '.agent')
    provider=$(jq -er '.agent' <<< "$agent")
    id=$(jq -er --arg provider "$provider" '
      .agent_session | select(.agent == $provider and .kind == "id") |
      .value | select(type == "string" and test("^[a-zA-Z0-9_-]+$"))' <<< "$agent") || id=
    # Claude already registers exact process/session identity for running agents.
    # Preserve forks from sessions started before herdr's identity hooks existed.
    if [[ -z $id && $provider == claude ]]; then
      processes=$(api pane process-info --pane "$pane_id")
      pid=$(jq -r '.process_info.foreground_processes[-1] | select(.name == "claude") | .pid // empty' <<< "$processes")
      if [[ $pid =~ ^[0-9]+$ ]]; then
        session_file=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$pid.json
        if [[ -f $session_file ]]; then
          id=$(jq -er '.sessionId | select(type == "string" and test("^[a-zA-Z0-9_-]+$"))' "$session_file") || id=
        fi
      fi
    fi
    [[ -n $id ]] || fail "No session identity for $provider in $pane_id. Install its herdr integration, then resume the agent in a fresh process before forking."
    case "$provider" in
      codex) command=(codex fork "$id");;
      claude)
        command=(claude --resume "$id" --fork-session)
        for transcript in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id.jsonl"; do
          [[ -f $transcript ]] || continue
          mode=$(jq -Rnr '[inputs | fromjson? | .permissionMode? // empty] | last // empty' < "$transcript")
          [[ -z $mode ]] || command+=(--permission-mode "$mode")
          break
        done
        ;;
      *) fail 'focused pane has no supported agent session';;
    esac
    cwd=$(jq -er '.foreground_cwd // .cwd' <<< "$pane")
    if [[ ${3:-} == --print-command ]]; then
      printf '%q ' "${command[@]}"
      printf '\n'
      exit 0
    fi
    if [[ $target == pane ]]; then
      result=$(api pane split --pane "$pane_id" --direction right --cwd "$cwd" --focus)
    else result=$(api tab create --cwd "$cwd" --focus); fi
    new=$(jq -er '(.pane // .root_pane).pane_id' <<< "$result")
    printf -v command_line '%q ' "${command[@]}"
    api pane run "$new" "$command_line" >/dev/null
    ;;
  *) fail 'expected launch or fork';;
esac
