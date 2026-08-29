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

case "$pane_cmd" in
  claude)
    session_id=$(claude_session_id || true)
    [ -n "$session_id" ] || die "no live claude session registered for $pane_ref"
    fork_cmd="claude --resume $session_id --fork-session"
    mode=$(claude_permission_mode "$session_id" || true)
    if [ -n "$mode" ]; then
      fork_cmd="$fork_cmd --permission-mode $mode"
    fi
    ;;
  *)
    die "no fork support for '$pane_cmd'"
    ;;
esac

case "$target" in
  pane) tmux split-window -h -c "$pane_path" "$fork_cmd" ;;
  window) tmux new-window -c "$pane_path" "$fork_cmd" ;;
  *) die "unknown target '$target' (expected pane or window)" ;;
esac
