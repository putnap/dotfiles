#!/usr/bin/env bash
# Fork the AI coding session running in the current pane into a new pane or window.
# Usage: agent-fork.sh [pane|window]
set -euo pipefail

target=${1:-pane}
# tmux run-shell does not export TMUX_PANE, so the binding passes the pane id.
pane=${2:-$(tmux display -p "#{pane_id}" 2>/dev/null || true)}

die() {
  tmux display-message "agent-fork: $*"
  exit 1
}

[ -n "$pane" ] || die "no target pane"

pane_ref=$(tmux display -p -t "$pane" '#{session_name}:#{window_id}.#{pane_id}')
pane_cmd=$(tmux display -p -t "$pane" '#{pane_current_command}')
pane_path=$(tmux display -p -t "$pane" '#{pane_current_path}')

# Claude Code registers every live session in ~/.claude/sessions/<pid>.json,
# including the tmux pane it runs in — no hook needed to map pane -> session.
claude_session_id() {
  jq -rs --arg pane "$pane_ref" '
    map(select(.tmux == $pane and .kind == "interactive"))
    | sort_by(.updatedAt) | reverse | .[] | "\(.pid) \(.sessionId)"
  ' "$HOME"/.claude/sessions/*.json 2>/dev/null |
    while read -r pid id; do
      # Pane ids get reused, so dead entries can still claim this pane.
      if kill -0 "$pid" 2>/dev/null; then
        echo "$id"
        break
      fi
    done
}

# Permission mode lives only in the transcript, so mirror the source session's last one.
claude_permission_mode() {
  local transcript
  transcript=$(ls "$HOME"/.claude/projects/*/"$1".jsonl 2>/dev/null | head -1)
  [ -n "$transcript" ] || return 0
  jq -r 'select(.permissionMode) | .permissionMode' "$transcript" 2>/dev/null | tail -1
}

record=$(tmux show-options -pqv -t "$pane" @workmux_hook)
identity=$(tmux display-message -p -t "$pane" '#{pane_pid} #{pane_current_command}')
provider=$(jq -r --arg identity "$identity" 'select(.identity == $identity) | .provider // empty' <<< "${record:-null}")
session_id=$(jq -r --arg identity "$identity" 'select(.identity == $identity) | .session // empty' <<< "${record:-null}")
if [[ -z $provider && $pane_cmd == claude ]]; then
  provider=claude
  session_id=$(claude_session_id || true)
fi
[[ $session_id =~ ^[a-zA-Z0-9_-]+$ ]] || die "no live agent session registered for $pane_ref"
case "$provider" in
  claude)
    command=(claude --resume "$session_id")
    [[ $target == resume-command ]] || command+=(--fork-session)
    mode=$(claude_permission_mode "$session_id" || true)
    [[ -z $mode ]] || command+=(--permission-mode "$mode")
    ;;
  codex)
    if [[ $target == resume-command ]]; then command=(codex resume "$session_id")
    else command=(codex fork "$session_id"); fi
    ;;
  *) die "no fork support for '$pane_cmd'";;
esac
printf -v fork_cmd '%q ' "${command[@]}"

case "$target" in
  resume-command) printf '%s\n' "$fork_cmd";;
  pane) tmux split-window -t "$pane" -h -c "$pane_path" "$fork_cmd" ;;
  window) tmux new-window -t "$pane" -c "$pane_path" "$fork_cmd" ;;
  *) die "unknown target '$target' (expected pane or window)" ;;
esac
