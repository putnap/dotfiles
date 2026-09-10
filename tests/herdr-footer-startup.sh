#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
cat > "$tmp/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == 'app-server --listen stdio:// -c model="test-model"' ]] || exit 9
while IFS= read -r line; do
  case $(jq -r '.id // empty' <<< "$line") in
    1) printf '%s\n' '{"id":1,"result":{}}';;
    2) printf '%s\n' '{"id":2,"result":{"config":{"model":"test-model","model_reasoning_effort":"high","approval_policy":"never","sandbox_mode":"danger-full-access"}}}';;
    3) printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":23,"windowDurationMins":10080},"secondary":null}}}';;
  esac
done
SH
chmod +x "$tmp/bin/codex"
PATH="$tmp/bin:$PATH" bash "$repo/herdr/.config/herdr/footer/codex-start-data.sh" "$tmp/state" -c 'model="test-model"'
jq -e '.model == "test-model" and .effort == "high" and .approval == "never" and .sandbox == "danger-full-access" and .weekly == 23 and .five_hour == null and (has("context")|not)' "$tmp/state/start-data.json" >/dev/null
printf '%s\n' 'startup metadata fixtures passed'
