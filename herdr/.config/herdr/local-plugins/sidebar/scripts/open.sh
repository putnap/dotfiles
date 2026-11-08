#!/usr/bin/env bash
# Opens the focused agent's Linear issue or pull request in the browser. Linear's links come
# from its bot's comment on the pull request, so only repositories wired to Linear have them;
# anywhere else a pull request opens on GitHub.
#
#   open.sh issue | open.sh pull-request
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
target=${1:?usage: open.sh <issue|pull-request>}

# Linear's bot links the issue and its review page, Linear's view of the pull request.
links_query='
  ([.body, .comments[].body] | map(. // "") | join(" ")) as $text
  | {github: .url,
     issue: ([$text | scan("https://linear\\.app/[A-Za-z0-9_-]+/issue/[A-Za-z]+-[0-9]+")] | first),
     review: ([$text | scan("https://linear\\.app/[A-Za-z0-9_-]+/review/[A-Za-z0-9_-]+")] | first)}'

workspace_query='
  [.[] | (.body, .comments[].body) | strings | scan("https://linear\\.app/([A-Za-z0-9_-]+)/")[0]]
  | first // empty'

main() {
  local pane dir ticket links url
  pane=$("$herdr" pane current | jq '.result.pane')
  dir=$(jq -r '.foreground_cwd // .cwd' <<< "$pane")
  ticket=$(jq -r '.tokens.ticket // ""' <<< "$pane")
  links=$(pull_request_links "$dir")
  case $target in
    issue) url=$(issue_url "$links" "$dir" "$ticket") ;;
    pull-request) url=$(jq -r '.review // .github // empty' <<< "$links") ;;
    *) echo "open.sh: unknown target: $target" >&2; exit 2 ;;
  esac
  if [[ -z $url ]]; then nothing_to_open "$dir"; fi
  open "$url"
}

pull_request_links() {
  (cd "$1" && gh pr view --json url,body,comments) 2>/dev/null | jq -c "$links_query" || printf '{}'
}

issue_url() {
  local links=$1 dir=$2 ticket=$3 url
  url=$(jq -r '.issue // empty' <<< "$links")
  if [[ -z $url ]]; then url=$(issue_from_ticket "$dir" "$ticket"); fi
  printf '%s' "$url"
}

# Before a branch has a pull request its ticket (the sidebar's $ticket) still names the issue;
# the Linear workspace is read off the repository's recent pull requests, which its bot links.
issue_from_ticket() {
  local dir=$1 ticket=$2 workspace
  if [[ ! $ticket =~ ^[A-Z]+-[0-9]+$ ]]; then return 0; fi
  workspace=$( (cd "$dir" && gh pr list --state all --limit 5 --json body,comments) 2>/dev/null | jq -r "$workspace_query" || true)
  if [[ -n $workspace ]]; then printf 'https://linear.app/%s/issue/%s' "$workspace" "$ticket"; fi
}

nothing_to_open() {
  local title
  case $target in
    issue) title="No Linear issue" ;;
    pull-request) title="No pull request" ;;
  esac
  exec "$herdr" notification show "$title" --body "for ${1##*/}" --sound none
}

main
