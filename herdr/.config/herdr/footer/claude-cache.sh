#!/usr/bin/env bash
# Fed by Claude's statusLine command for the tmux footer. No model content is stored.
set -euo pipefail
input=$(cat)
[[ -n ${HERDR_SOCKET_PATH:-}${TMUX:-} ]] || exit 0
source "$(dirname "$0")/state-dir.sh"
mkdir -p "$root/claude"
chmod 700 "$root/claude"
id=$(jq -er '.session_id | select(test("^[a-zA-Z0-9_-]+$"))' <<< "$input")
transcript=$(jq -r '.transcript_path // empty' <<< "$input")
permission=null
if [[ -f $transcript ]]; then
  permission=$(rg '"permissionMode"\s*:' "$transcript" | jq -c 'select(.permissionMode != null) | .permissionMode' | tail -n 1) || permission=null
fi
[[ -n $permission ]] || permission=null
file=$(mktemp "$root/claude/.sample.XXXXXX")
trap 'rm -f "$file"' EXIT
jq --argjson permission "$permission" --arg transcript "$transcript" '{session_id, permission:$permission,
 transcript:($transcript | select(. != "")), cwd:(.workspace.current_dir // .cwd), model:.model.display_name, effort:.effort.level,
 context:.context_window.used_percentage, five_hour:.rate_limits.five_hour.used_percentage,
 weekly:.rate_limits.seven_day.used_percentage,
 five_hour_resets_at:.rate_limits.five_hour.resets_at,
 weekly_resets_at:.rate_limits.seven_day.resets_at, measured_at:now}' <<< "$input" > "$file"
mv "$file" "$root/claude/$id.json"
