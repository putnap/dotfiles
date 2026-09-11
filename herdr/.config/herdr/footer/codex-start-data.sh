#!/usr/bin/env bash
# Read-only app-server requests; never starts a thread or sends a prompt.
set -euo pipefail
umask 077
dir=${1:?}
shift
tmp=$(mktemp -d "$dir/.rpc.XXXXXX")
pid=
cleanup() { [[ -z $pid ]] || kill "$pid" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
mkfifo "$tmp/in" "$tmp/out"
codex app-server --listen stdio:// "$@" <"$tmp/in" >"$tmp/out" 2>"$tmp/stderr" &
pid=$!
exec 3>"$tmp/in" 4<"$tmp/out"
printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"herdr-footer","version":"1"}}}' >&3
while IFS= read -r -t 10 line <&4; do
  [[ $(jq -r '.id // empty' <<< "$line") == 1 ]] || continue
  jq -e 'has("result")' <<< "$line" >/dev/null || exit 1
  break
done
printf '%s\n' '{"method":"initialized"}' >&3
jq -nc --arg cwd "$PWD" '{id:2,method:"config/read",params:{cwd:$cwd,includeLayers:false}}' >&3
printf '%s\n' '{"id":3,"method":"account/rateLimits/read"}' >&3
count=0
while IFS= read -r -t 10 line <&4; do
  case $(jq -r '.id // empty' <<< "$line") in
    2) jq '{model:.result.config.model, effort:.result.config.model_reasoning_effort, approval:.result.config.approval_policy, sandbox:.result.config.sandbox_mode}' <<< "$line" > "$tmp/config"; count=$((count+1));;
    3) jq '{rate_limits:(.result.rateLimitsByLimitId.codex // .result.rateLimits)}' <<< "$line" > "$tmp/limits"; count=$((count+1));;
  esac
  ((count < 2)) || break
done
[[ -f $tmp/config && -f $tmp/limits ]] || exit 1
jq -s '.[0] * .[1] | .rate_limits as $r |
 def window($mins): [$r.primary,$r.secondary] | map(select(.windowDurationMins == $mins)) | .[0];
 . + {measured_at:now, has_credits:$r.credits.hasCredits,
 five_hour:window(300).usedPercent, weekly:window(10080).usedPercent,
 five_hour_resets_at:window(300).resetsAt, weekly_resets_at:window(10080).resetsAt} | del(.rate_limits)' "$tmp/config" "$tmp/limits" > "$tmp/sample"
mv "$tmp/sample" "$dir/start-data.json"
