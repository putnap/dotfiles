#!/usr/bin/env bash
# The sidebar plugin's open actions, through a temporary server: a repository wired to Linear
# opens its issue and review page, a branch without a pull request still finds its issue, and a
# GitHub-only repository opens its pull request there. gh and open are stubs; git is real.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-links.XXXXXX)
export HERDR_CONFIG_PATH=$scratch/config.toml HERDR_SOCKET_PATH=$scratch/herdr.sock
export XDG_CONFIG_HOME=$scratch/xdg XDG_STATE_HOME=$scratch/state XDG_DATA_HOME=$scratch/data XDG_CACHE_HOME=$scratch/cache
cat > "$HERDR_CONFIG_PATH" <<'CONFIG'
[ui.toast]
delivery = "off"
[ui.sound]
enabled = false
[terminal]
default_shell = "/bin/sh"
shell_mode = "non_login"
CONFIG
mkdir -p "$scratch/bin"
cat > "$scratch/bin/gh" <<'STUB'
#!/bin/sh
# The sidebar's own pull request lookups find nothing; the open actions get the pull request.
case "$*" in *number,state,isDraft*) exit 1 ;; esac
branch=$(git symbolic-ref --short -q HEAD)
project=$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")
case "$1 $2 $branch" in
  "pr view feature/eng-8-work")
    echo '{"url":"https://github.com/acme/work/pull/8","body":"","comments":[{"body":"<a href=\"https://linear.app/acme/issue/ENG-8/work-thing\">ENG-8</a> <a href=\"https://linear.app/acme/review/work-thing-abc123?openGuide=true\">Review</a>"}]}' ;;
  "pr view fix/tidy")
    echo '{"url":"https://github.com/me/home/pull/3","body":"","comments":[]}' ;;
  "pr list "*)
    if [ "$project" = work ]; then echo '[{"body":"see https://linear.app/acme/issue/ENG-1/old","comments":[]}]'; else echo '[]'; fi ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "%s/opened"\n' "$scratch" > "$scratch/bin/open"
chmod +x "$scratch/bin/gh" "$scratch/bin/open"
commit() { git -C "$1" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init; }
git init -q -b feature/eng-8-work "$scratch/work" && commit "$scratch/work"
git -C "$scratch/work" worktree add -q -b feature/eng-9-fresh "$scratch/work-fresh"
git init -q -b fix/tidy "$scratch/home" && commit "$scratch/home"
PATH=$scratch/bin:$PATH herdr server > "$scratch/server.log" 2>&1 &
server=$!
cleanup() {
  herdr server stop >/dev/null 2>&1 || kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
for ((i=0;i<100;i++)); do
  [[ ! -S $HERDR_SOCKET_PATH ]] || break
  sleep 0.1
done
herdr plugin link "$repo/herdr/.config/herdr/local-plugins/sidebar" >/dev/null

work=$(herdr workspace create --cwd "$scratch/work" --label work | jq -er '.result.root_pane.pane_id')
fresh=$(herdr pane split "$work" --direction right --cwd "$scratch/work-fresh" | jq -er '.result.pane.pane_id')
home=$(herdr workspace create --cwd "$scratch/home" --label home | jq -er '.result.root_pane.pane_id')
for pane in "$work" "$fresh" "$home"; do
  herdr pane report-agent "$pane" --source custom:test --agent claude --state idle >/dev/null
done
for ((i=0;i<100;i++)); do
  [[ $(herdr agent list | jq -r --arg pane "$fresh" '.result.agents[] | select(.pane_id == $pane) | .tokens.ticket // ""') != ENG-9 ]] || break
  sleep 0.1
done

# open_from PANE ACTION: the URL the action opened for that pane, or "nothing".
open_from() {
  local runs
  : > "$scratch/opened"
  herdr agent focus "$1" >/dev/null
  runs=$(herdr plugin log list | jq '[.result.logs[] | select(.action_id == "'"$2"'")] | length')
  herdr plugin action invoke "sidebar.$2" >/dev/null
  for ((i=0;i<100;i++)); do
    herdr plugin log list | jq -e --arg action "$2" --argjson runs "$runs" \
      '[.result.logs[] | select(.action_id == $action and .status != "running")] | length > $runs' >/dev/null && break
    sleep 0.1
  done
  if [[ -s $scratch/opened ]]; then cat "$scratch/opened"; else echo nothing; fi
}
expect() {
  local want=$1 got=$2 what=$3
  [[ $got == "$want" ]] || { echo "$what: expected $want, got $got" >&2; exit 1; }
}

expect https://linear.app/acme/issue/ENG-8 "$(open_from "$work" open-issue)" 'Linear issue from the pull request'
expect https://linear.app/acme/review/work-thing-abc123 "$(open_from "$work" open-pull-request)" 'pull request in Linear'
expect https://linear.app/acme/issue/ENG-9 "$(open_from "$fresh" open-issue)" 'Linear issue before a pull request'
expect nothing "$(open_from "$fresh" open-pull-request)" 'no pull request yet'
expect https://github.com/me/home/pull/3 "$(open_from "$home" open-pull-request)" 'pull request on GitHub'
expect nothing "$(open_from "$home" open-issue)" 'no Linear outside Linear repositories'
printf '%s\n' 'sidebar links passed: Linear issue and review, issue before a pull request, GitHub elsewhere'
