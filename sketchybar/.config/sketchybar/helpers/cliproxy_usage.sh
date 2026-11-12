#!/usr/bin/env bash
# The account papulab's CLIProxyAPI sends new sessions to, and its 5h / 7d / Fable-week usage,
# as "pickitoo.com 47/25/52%". Prints nothing when the proxy can't be asked.
set -euo pipefail

PROXY=http://papulab.tail0d6b22.ts.net/v8/management

ask() {
  curl -sf -m 10 -H "Authorization: Bearer $(cat ~/.cli-proxy-api/management-key)" -H 'Content-Type: application/json' "$@"
}

# The highest priority Claude account free to take a session, as {index, name}.
account_in_use() {
  ask "$PROXY/credentials" | jq -c '
    [.files[] | select(.provider == "claude" and (.disabled | not) and (.quota_blocked | not) and (.cooldowns | length == 0))]
    | max_by(.priority // 0) // empty
    | {index: .auth_index, name: ((.label // .email) | split("@") | last)}'
}

# The proxy asks Anthropic with the account's own token.
usage_of() {
  local request
  request=$(jq -nc --arg index "$1" '{auth_index: $index, method: "GET", url: "https://api.anthropic.com/api/oauth/usage",
    header: {Authorization: "Bearer $TOKEN$", "anthropic-beta": "oauth-2025-04-20"}}')
  ask -X POST "$PROXY/requests/api-call" -d "$request" | jq -r '
    select(.status_code == 200) | .body | fromjson
    | "\(.five_hour.utilization // 0 | round)/\(.seven_day.utilization // 0 | round)/\([.limits[]? | select(.kind == "weekly_scoped" and .scope.model.display_name == "Fable") | .percent][0] // 0 | round)%"'
}

account=$(account_in_use)
if [ -n "$account" ]; then
  echo "$(jq -r .name <<<"$account") $(usage_of "$(jq -r .index <<<"$account")")"
fi
