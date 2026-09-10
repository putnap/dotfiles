#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scripts=$repo/herdr/.config/herdr/footer
sample='{"info":{"model_context_window":258400,"last_token_usage":{"total_tokens":15634}},"rate_limits":{"primary":{"window_minutes":10080,"used_percent":22}}}'
jq -c -f "$scripts/codex-metrics.jq" <<< "$sample" | jq -e '.context == 1 and .five_hour == null and .weekly == 22' >/dev/null
jq -c -f "$scripts/codex-metrics.jq" <<< '{}' | jq -e '.context == null and .five_hour == null and .weekly == null' >/dev/null
printf '%s\n' '{"type":"turn_context","payload":{"model":"test","effort":"high","approval_policy":"never","sandbox_policy":{"type":"danger-full-access"}}}' '{"type":"response_item","payload":{"text":"must not remain"}}' 'invalid' |
  jq -Rnc --argjson previous '[{}]' -f "$scripts/collect.jq" |
  jq -e '. == {model:"test",effort:"high",cwd:null,approval:"never",sandbox:"danger-full-access"}' >/dev/null
printf '%s\n' 'metric fixtures passed'
