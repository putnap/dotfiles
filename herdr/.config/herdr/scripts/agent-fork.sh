#!/usr/bin/env bash
# Fork the AI coding session running in the focused pane into a new pane or tab.
# Usage: agent-fork.sh [pane|tab]
# Herdr port of ~/.config/tmux/scripts/agent-fork.sh.
set -euo pipefail

target=${1:-pane}

die() {
  herdr notification show "agent-fork" --body "$*" --sound request
  exit 1
}

# keys.command shells run detached without pane context, so resolve the pane
# herdr currently has focused -- which is the one the key was pressed in.
pane_json=$(herdr pane current)
pane_id=$(jq -r '.result.pane.pane_id' <<<"$pane_json")
pane_path=$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$pane_json")

proc_json=$(herdr pane process-info --pane "$pane_id")
pane_cmd=$(jq -r '.result.process_info.foreground_processes[-1].name // ""' <<<"$proc_json")
pane_pid=$(jq -r '.result.process_info.foreground_processes[-1].pid // ""' <<<"$proc_json")

# Permission mode lives only in the transcript, so mirror the source session's last one.
claude_permission_mode() {
  local transcript
  transcript=$(ls "$HOME"/.claude/projects/*/"$1".jsonl 2>/dev/null | head -1)
  [ -n "$transcript" ] || return 0
  jq -r 'select(.permissionMode) | .permissionMode' "$transcript" 2>/dev/null | tail -1
}

case "$pane_cmd" in
  claude)
    # Claude Code registers every live session at ~/.claude/sessions/<pid>.json,
    # so the pane's foreground pid is the whole lookup -- no hook needed.
    session_file="$HOME/.claude/sessions/$pane_pid.json"
    [ -f "$session_file" ] || die "no live claude session registered for pid $pane_pid"
    session_id=$(jq -r '.sessionId' "$session_file")
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
  pane) new_json=$(herdr pane split --pane "$pane_id" --direction right --cwd "$pane_path" --focus) ;;
  tab) new_json=$(herdr tab create --cwd "$pane_path" --focus) ;;
  *) die "unknown target '$target' (expected pane or tab)" ;;
esac

new_pane=$(jq -r '.result.pane.pane_id // .result.root_pane.pane_id' <<<"$new_json")
herdr pane run "$new_pane" "$fork_cmd"
