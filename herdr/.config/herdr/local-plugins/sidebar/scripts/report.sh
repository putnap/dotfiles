#!/usr/bin/env bash
# Draws the sidebar's tree (tree.jq) into each space's rows: its agents, its other checkouts
# with their tickets and pull requests, and a pointer on the row the focus is on. Turns the
# agent panel into the inbox of pinned, blocked, done and unread agents, and reports each
# agent's title, $pin, $unread, $reason, $ticket and project name for it.
# `report.sh rows` redraws the rows and the title of the pane an event names, from the last full
# run's tickets and pull requests, for focus and title changes. Overlapping runs each start from a fresh snapshot.
set -euo pipefail

herdr=${HERDR_BIN_PATH:-herdr}
state=${HERDR_PLUGIN_STATE_DIR:?}
source "$(dirname "$0")/tree.sh"
separator=$'\x1f'
# Rows under a space's own; herdr draws at most 16 a space.
tree_rows=15
# Session ids or pane ids, one a line, in the order pin.sh pinned them.
pins=$state/pins
# Each checkout's ticket and pull request as the last full run found them, for `rows`.
details_file=$state/checkout-details.json
# Nerd Font's pushpin, before a pinned agent's title.
pin_mark=$'\xef\x90\xb5'
# $unread's value. herdr's done ends at a glance; a reply finished out of sight stays unread
# until the agent works again or acknowledge.sh marks it read.
unread_mark='✓'

# The hues of herdr's catppuccin colours; a project takes the one nearest its favicon's. Six,
# far enough apart to tell at a glance.
brand_hues='red 343 peach 23 green 115 teal 170 blue 217 mauve 267'

agents_query='
  (.workspaces | map({(.workspace_id): (.label // "")}) | add) as $labels
  | .agents[] | select($only == "" or .pane_id == $only)
  | (.agent_session.value // .pane_id) as $key
  | ($pins | index($key)) as $pin
  | (.agent_status == "done" or ((.tokens.unread // "") != "" and .agent_status != "working")) as $unread
  | [.pane_id, (.foreground_cwd // .cwd // ""), $labels[.workspace_id], ($brands[.workspace_id] // "plain"),
     ((if $pin == null then "" else $mark + " " end) + (.terminal_title_stripped // "")
       | gsub("^\\s+|\\s+$"; "") | .[0:80] | gsub("\\s+$"; "")),
     .agent_status,
     (if $pin == null then "" else "000\($pin + 1)" | .[-4:] end),
     (if $unread then $unread_mark else "" end), (.agent // ""), (.agent_session.value // ""),
     (.tokens // {} | tojson)]
  | join("\u001f")'

# Only workspaces herdr has tied to a checkout carry .worktree; the rest use their first pane's folder.
workspaces_query='
  (.panes | group_by(.workspace_id) | map({(.[0].workspace_id): (.[0].cwd // "")}) | add) as $first_cwd
  | .workspaces[]
  | [.workspace_id, (.worktree.checkout_path // $first_cwd[.workspace_id] // ""), (.label // ""),
     (.tokens // {} | tojson)]
  | join("\u001f")'

# "open #12", "draft #12", "merged #12" or "closed #12": GitHub's own four states.
pull_request_state='
  (if .state != "OPEN" then .state | ascii_downcase elif .isDraft then "draft" else "open" end)
  + " #\(.number)"'

# The inbox: pinned agents in pin order, then blocked, done and unread ones newest first.
# Agents without $pin sort after those with one. tree.jq's inbox keeps the same order for
# navigate.sh.
inbox_view='{id: "sidebar:view", method: "agent.view.set", params: {
  source: "plugin:sidebar", label: "inbox",
  filter: {op: "any", filters: [{op: "in", field: "status", values: ["blocked", "done"]},
                                {op: "exists", field: {token: "pin"}},
                                {op: "exists", field: {token: "unread"}}]},
  sort: [{field: {token: "pin"}, order: "asc"}, {field: "state_change_seq", order: "desc"}]}}'

# {workspace_id: tokens}, each space's tokens set or cleared. The first row is config.toml's
# own; the rest are tree rows, each the tree's lines and a state glyph, or "▸" for the row the
# focus is on, with a heavy line on the worktree it is in. herdr trims a value's leading
# spaces, so a row under the last worktree starts with a blank that isn't one (U+2800). A space
# herdr nests under its repository indents every row under its name by 8 columns, so one with a
# single agent shows that agent's title on its name row instead, as $lead_*. The name is the
# plugin's own, $name or $name_focused: herdr names a nested space by its whole branch, which
# leaves the title no room, so a nested space goes by its ticket. Rows go
# only as far down as the space draws now or did before, since each request costs a redraw's
# time; a focus move keeps their number.
space_token_defs='
  def glyph: if .here then "▸" else {blocked: "×", working: "●", done: "✓", idle: "○"}[.status] // "·" end;
  def agent_line($indent): $indent + glyph + " " + .title;
  def ticket_part($ticket; $name):
    if $ticket == "" or $ticket == "main" or $ticket == "master"
      or ($name | ascii_upcase | contains($ticket | ascii_upcase)) then "" else " · " + $ticket end;
  def connector:
    {here: {last: "└▸ ", middle: "├▸ "}, active: {last: "┕━ ", middle: "┝━ "}, other: {last: "└─ ", middle: "├─ "}}
    [if .here then "here" elif .active then "active" else "other" end][if .last then "last" else "middle" end];
  def header_line: connector + .name
    + ticket_part($details[.checkout].ticket // ""; .name);
  def lines:
    [(.agents[] | {text: agent_line("")}),
     (.groups[] | .last as $last
       | {text: header_line, pr: ($details[.checkout].pr // "")},
         (.agents[] | {text: agent_line(if $last then "\u2800 " else "│ " end)}))];
  def fitted: if length <= $rows then . else .[0:$rows - 1] + [{text: "… \(length - $rows + 1) more"}] end;
  def one_of($prefix; $chosen; $value; $names):
    $names[] | {"\($prefix)_\(.)": (if . == $chosen then $value else "" end)};
  def pull_request_tokens($prefix; $pr):
    one_of($prefix; ($pr | split(" ") | .[0]); ($pr | split(" ") | .[1] // ""); ["open", "draft", "merged", "closed"]);
  def rows_drawn: [.drawn | keys[] | capture("^row_(?<row>[0-9]+)").row | tonumber] | max // 0;
  def lead: if .nested and (.groups | length) == 0 and (.agents | length) == 1 then .agents[0] else null end;
  def lead_tokens:
    lead as $agent
    | one_of("lead"; ({done: "unread", working: "active", blocked: "active"}[$agent.status // ""] // "idle");
             ($agent.title // "" | .[0:80] | sub("\\s+$"; "")); ["unread", "active", "idle"]);
  def space_ticket:
    ($details[.checkout].ticket // "") as $ticket
    | if .nested or ($ticket != "" and (.label | ascii_upcase | contains($ticket | ascii_upcase))) then "" else $ticket end;
  def name_tokens:
    (if .nested then $details[.checkout].ticket // "" else "" end | if . == "" then null else . end) as $short
    | ($short // .label) as $name
    | {name_focused: (if .focused then $name else "" end), name: (if .focused then "" else $name end)};
  def space_tokens:
    ($details[.checkout] // {}) as $home | (if lead == null then lines | fitted else [] end) as $lines
    | ([($lines | length), rows_drawn] | max) as $reach
    | [name_tokens, {ticket: space_ticket}, lead_tokens,
       pull_request_tokens("pr"; $home.pr // ""),
       (range(1; $reach + 1) as $row | ($lines[$row - 1] // {}) as $line
         | {"row_\($row)": ($line.text // "" | .[0:80] | sub("\\s+$"; ""))},
           pull_request_tokens("row_\($row)_pr"; $line.pr // ""))]
    | add;
  def rows_tokens: [.spaces[] | {(.workspace_id): space_tokens}] | add // {};'

# The whole draw in one jq, since on a busy machine each process costs most of the time: from
# herdr's snapshot, or its answer carrying one, the tree, every space's tokens and the requests
# that report them. The first line says which folders and checkouts it had nothing on, so that
# draw looks them up and goes again before sending; on a focus change there are none.
draw_query="include \"tree\"; $space_token_defs $request_defs"'
  (.result.snapshot // .) as $snapshot
  | ($snapshot | tree($checkouts)) as $tree
  | {new: ($snapshot | new_folders($checkouts)),
     missing: ([$tree.spaces[] | .checkout, .groups[].checkout] | unique | map(select(. != "" and $details[.] == null)))}
    as $unknown
  | ($unknown | tojson), ($tree | rows_tokens | request_lines($sequence))'

report_everything() {
  local sequence snapshot brands
  sequence=$(report_sequence)
  show_inbox
  order_spaces_as_tree
  snapshot=$("$herdr" api snapshot | jq '.result.snapshot')
  brands=$(project_brands "$snapshot")
  report_agents "$snapshot" "$brands"
  forget_checkouts
  draw "$snapshot" '{}' 5 "$sequence"
  plan_presses "$snapshot" "$sequence"
}

# `report.sh rows-for PANE`, the snapshot on stdin: the rows' tokens as if PANE had the focus,
# for a press navigate.sh found no plan for.
print_rows_for() {
  space_tokens "$(tree "$(focused_on "$1")")" "$(saved_details)"
}

# pane.focused: the focus marker moved, so this redraws from the saved details and touches
# only the named pane's title. The draw goes first; planning and the title after, so they
# don't slow it.
refresh_rows() {
  local sequence answer snapshot only pane dir label brand title status pin unread agent session current
  sequence=$(report_sequence)
  answer=$("$herdr" api snapshot)
  draw "$answer" "$(saved_details)" any "$sequence"
  snapshot=$(jq '.result.snapshot' <<< "$answer")
  plan_presses "$snapshot" "$sequence"
  only=$(jq -r '.data.pane.pane_id // .data.pane_id // ""' <<< "${HERDR_PLUGIN_EVENT_JSON:-null}")
  if [[ -n $only ]]; then
    while IFS=$separator read -r pane dir label brand title status pin unread agent session current; do
      title_tokens "$status" "$unread" "$title" | report pane "$pane" "$current"
    done < <(agents "$snapshot" '{}' "$only")
  fi
}

# A view lasts until the server exits and has no CLI, so each run sets it over the socket;
# that also covers a plugin linked mid-session, whose startup hook never ran.
show_inbox() {
  jq -cn "$inbox_view" | /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
}

# herdr's collapsed sidebar draws its own order, not the tree's that shift+up/down walks, so a
# repository's worktree spaces are moved to follow it there too. One at a time, in order.
order_spaces_as_tree() {
  local request
  "$herdr" api snapshot | jq -c -L "$scripts_dir" 'include "tree"; .result.snapshot | space_moves[]' |
    while IFS= read -r request; do send_request "$request"; done
}

# draw INPUT DETAILS PULL_REQUEST_MINUTES SEQUENCE: every space's rows from INPUT, herdr's
# snapshot or its answer carrying one, sent. Each row goes whole, not just its changed tokens, so
# that whichever run read the newest snapshot wins, even over a slower run that read an older
# one. DETAILS are the checkouts' tickets and pull requests known so far.
draw() {
  local output unknown requests=""
  output=$(jq -r -L "$scripts_dir" --argjson checkouts "$(known_checkouts)" --argjson details "$2" \
    --argjson rows "$tree_rows" --argjson sequence "$4" "$draw_query" <<< "$1")
  unknown=${output%%$'\n'*}
  if [[ $output == *$'\n'* ]]; then requests=${output#*$'\n'}; fi
  if [[ $unknown == '{"new":[],"missing":[]}' ]]; then
    send_requests <<< "$requests"
  else
    learn_checkouts "$(jq -c '.new' <<< "$unknown")"
    draw "$1" "$(learn_details "$2" "$(jq -c '.missing' <<< "$unknown")" "$3")" "$3" "$4"
  fi
}

# space_tokens TREE DETAILS
space_tokens() {
  jq -c --argjson details "$2" --argjson rows "$tree_rows" "$space_token_defs rows_tokens" <<< "$1"
}

# plan_presses SNAPSHOT SEQUENCE: where each press would land from here and which tokens it
# changes, so that a press (navigate.sh) only sends those, with no snapshot of its own. Both
# presses' rows are drawn in one go, as two snapshots through the same steps. A plan only
# replaces one from an older redraw.
plan_presses() {
  local focused tree details tokens landings rows
  focused=$(jq -r '.focused_pane_id // ""' <<< "$1")
  tree=$(tree "$1")
  details=$(saved_details)
  tokens=$(space_tokens "$tree" "$details")
  landings=$(bash "$(dirname "$0")/navigate.sh" landings "$focused" <<< "$tree")
  rows=$(space_tokens "$(tree "$(jq -c --argjson landings "$landings" \
    '.focused_pane_id as $here | (.focused_pane_id = ($landings.next.pane // $here)), (.focused_pane_id = ($landings.previous.pane // $here))' \
    <<< "$1")")" "$details")
  keep_plan "$(jq -cs --argjson landings "$landings" --argjson before "$tokens" --arg from "$focused" --argjson sequence "$2" '
    def changed($after): $after | to_entries
      | map(.key as $space | .value |= with_entries(select(.value != ($before[$space][.key] // ""))))
      | map(select(.value != {})) | from_entries;
    def plan($landing; $after): if $landing == null then null else {landing: $landing, tokens: changed($after)} end;
    {sequence: $sequence, from: $from, next: plan($landings.next; .[0]), previous: plan($landings.previous; .[1])}' <<< "$rows")" "$2"
}

keep_plan() {
  local kept
  kept=$(jq -r '.sequence' "$plans_file" 2>/dev/null || printf 0)
  if (( $2 > kept )); then
    printf '%s\n' "$1" > "$plans_file.$$"
    mv "$plans_file.$$" "$plans_file"
  fi
}

# The snapshot on stdin, as if PANE had the focus.
focused_on() {
  jq --arg pane "$1" '.focused_pane_id = $pane'
}

# {checkout: {ticket, pr}} as last looked up. A full run starts from none, so it looks every
# checkout up afresh; a focus change looks up only a checkout new since, from cached pull requests.
saved_details() {
  local saved=""
  if [[ -f $details_file ]]; then saved=$(<"$details_file") || true; fi
  if [[ -z $saved ]]; then saved='{}'; fi
  printf '%s' "$saved"
}

# learn_details DETAILS CHECKOUTS PULL_REQUEST_MINUTES: DETAILS with CHECKOUTS, a JSON list,
# looked up, kept for the next run. Written aside and moved in, so a run never reads half.
learn_details() {
  local details
  details=$(jq -r '.[]' <<< "$2" | look_up_details "$3" | jq -c --argjson known "$1" '$known + .')
  printf '%s' "$details" > "$details_file.$$"
  mv "$details_file.$$" "$details_file"
  printf '%s' "$details"
}

# Reads checkouts, one a line; PULL_REQUEST_MINUTES as pull_request takes it.
look_up_details() {
  local checkout branch
  while IFS= read -r checkout; do
    branch=$(current_branch "$checkout")
    jq -cn --arg checkout "$checkout" --arg ticket "$(ticket_of "$branch")" \
      --arg pr "$(pull_request "$checkout" "$branch" "$1")" '{($checkout): {ticket: $ticket, pr: $pr}}'
  done | jq -s 'add // {}'
}

# {workspace_id: colour name}. A favicon picks a project's colour; a project without one is
# given, at random, a colour no open project has yet, and keeps it. Only a full pool repeats.
project_brands() {
  local projects used workspace key favicon colour
  projects=$(project_list "$1")
  used=$(colours_in_use "$projects")
  while IFS=$separator read -r workspace key favicon; do
    if [[ -z $workspace ]]; then continue; fi
    colour=$(project_colour "$key" "$favicon" "$used")
    used="$used $colour"
    printf '%s %s\n' "$workspace" "$colour"
  done <<< "$projects" | jq -Rn '[inputs | split(" ") | {(.[0]): .[1]}] | add // {}'
}

# Lines of workspace id, project key and favicon colour; worktrees share their repository's key.
project_list() {
  local workspace dir label current
  while IFS=$separator read -r workspace dir label current; do
    printf '%s\x1f%s\x1f%s\n' "$workspace" "$(project_key "$dir")" "$(favicon_brand "$dir")"
  done < <(jq -r "$workspaces_query" <<< "$1")
}

colours_in_use() {
  local workspace key favicon
  while IFS=$separator read -r workspace key favicon; do
    if [[ $favicon != plain ]]; then
      printf '%s ' "$favicon"
    elif [[ -f $(assignment_file "$key") ]]; then
      printf '%s ' "$(cat "$(assignment_file "$key")")"
    fi
  done <<< "$1"
}

project_colour() {
  local key=$1 favicon=$2 used=$3 file
  if [[ $favicon != plain || -z $key ]]; then printf '%s' "$favicon"; return 0; fi
  file=$(assignment_file "$key")
  if [[ ! -f $file ]]; then
    mkdir -p "${file%/*}"
    random_free_colour "$used" > "$file.$$"
    # -n: when overlapping runs both pick one, the first to land is the one kept.
    mv -n "$file.$$" "$file"
    rm -f "$file.$$"
  fi
  cat "$file"
}

random_free_colour() {
  local used=" $1 " free=() name
  for name in $(brand_names); do
    if [[ $used != *" $name "* ]]; then free+=("$name"); fi
  done
  if ((${#free[@]} == 0)); then free=($(brand_names)); fi
  printf '%s' "${free[RANDOM % ${#free[@]}]}"
}

assignment_file() {
  printf '%s/assigned-colours/%s' "$state" "${1//\//_}"
}

project_key() {
  if [[ -z $1 ]]; then return 0; fi
  repository_key "$1" 2>/dev/null || printf '%s' "$1"
}

report_agents() {
  local pane dir label brand title status pin unread agent session current branch
  while IFS=$separator read -r pane dir label brand title status pin unread agent session current; do
    branch=$(current_branch "$dir")
    {
      title_tokens "$status" "$unread" "$title"
      printf 'pin=%s\n' "$pin"
      printf 'unread=%s\n' "$unread"
      printf 'reason=%s\n' "$(reason "$status" "$unread" "$agent" "$session")"
      printf 'ticket=%s\n' "$(ticket_of "$branch")"
      one_token_of project "$brand" "$label" plain $(brand_names)
    } | report pane "$pane" "$current"
  done < <(agents "$1" "$2" "")
}

# agents SNAPSHOT BRANDS ONLY: one line per agent, or only the pane ONLY when it is set.
agents() {
  jq -r --argjson brands "$2" --arg only "$3" --argjson pins "$(pinned)" --arg mark "$pin_mark" \
    --arg unread_mark "$unread_mark" "$agents_query" <<< "$1"
}

pinned() {
  if [[ -f $pins ]]; then jq -Rn '[inputs]' < "$pins"; else printf '[]'; fi
}

# Reads name=value lines. Only changed values are sent, so a quiet session costs no herdr
# calls; an empty value clears the token.
report() {
  local kind=$1 id=$2 current=$3 pair arguments=()
  while IFS= read -r pair; do arguments+=(--token "$pair"); done < <(changed_tokens "$current")
  if ((${#arguments[@]} > 0)); then
    report_metadata "$kind" report-metadata "$id" --source plugin:sidebar "${arguments[@]}"
  fi
}

changed_tokens() {
  jq -Rr --argjson current "$1" 'capture("^(?<name>[^=]*)=(?<value>.*)$")
    | select(($current[.name] // "") != .value) | "\(.name)=\(.value)"'
}

# A pane or workspace can close between the snapshot and its report; the run its closing
# starts covers what is left, so only that error is let through.
report_metadata() {
  local output
  output=$("$herdr" "$@" 2>&1) || grep -q '_not_found"' <<< "$output" || { printf '%s\n' "$output" >&2; return 1; }
}

# one_token_of PREFIX CHOSEN VALUE NAMES...: config.toml colours each PREFIX_NAME token on its
# own, since rules can't pick a colour any other way; only CHOSEN carries VALUE, the rest clear.
one_token_of() {
  local prefix=$1 chosen=$2 value=$3 name
  shift 3
  for name in "$@"; do
    if [[ $name == "$chosen" ]]; then
      printf '%s_%s=%s\n' "$prefix" "$name" "$value"
    else
      printf '%s_%s=\n' "$prefix" "$name"
    fi
  done
}

# The title stays bright while the agent works, is blocked or has a reply unread, and dims once
# it is idle and read. The copy is trimmed and cut the way herdr stores it, or every refresh
# would find it changed.
title_tokens() {
  local status=$1 unread=$2 title=$3 chosen=active
  if [[ $status == idle && -z $unread ]]; then chosen=idle; fi
  one_token_of title "$chosen" "$title" active idle
}

# reason STATUS UNREAD AGENT SESSION: for an inbox row, why it waits: the question or tool a
# blocked agent asks about, or the last line of an unread reply. Only Claude's are read.
reason() {
  local transcript
  if [[ $1 != blocked && -z $2 ]] || [[ $3 != claude || -z $4 ]]; then return 0; fi
  transcript=$(claude_transcript "$4")
  if [[ -n $transcript ]]; then tail -n 200 "$transcript" | jq -nRr -f "$(dirname "$0")/reason.jq"; fi
}

claude_transcript() {
  local match
  for match in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl; do
    if [[ -f $match ]]; then printf '%s' "$match"; return 0; fi
  done
}

brand_names() {
  awk '{ for (i = 1; i <= NF; i += 2) print $i }' <<< "$brand_hues"
}

current_branch() {
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true
}

# Branches carry Linear ids (feature/eng-2919-flag-ui), which say more in less room than the
# branch; one without an id shows its last segment.
ticket_of() {
  local branch=$1
  if [[ $branch =~ ([A-Za-z]+-[0-9]+) ]]; then
    tr '[:lower:]' '[:upper:]' <<< "${BASH_REMATCH[1]}"
  else
    printf '%s' "${branch##*/}"
  fi
}

# pull_request DIR BRANCH MINUTES: gh is slow and rate-limited, so each branch's answer, even
# "none", is kept MINUTES; "any" takes a cached one of any age and asks gh only without one.
pull_request() {
  local dir=$1 branch=$2 minutes=$3
  if [[ -z $branch ]]; then return 0; fi
  if [[ $minutes == any ]]; then minutes=525600; fi
  cached pull-request-states "$(repository_key "$dir")@$branch" "$minutes" lookup_pull_request "$dir" "$branch"
}

lookup_pull_request() {
  (cd "$1" && gh pr view "$2" --json number,state,isDraft --jq "$pull_request_state") 2>/dev/null || true
}

# A favicon rarely changes, so its colour is kept for a day.
favicon_brand() {
  local dir=$1
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then printf plain; return 0; fi
  cached brands "$(repository_key "$dir")" 1440 lookup_brand "$dir"
}

lookup_brand() {
  local favicon
  favicon=$(find_favicon "$1")
  if [[ -z $favicon ]]; then printf plain; return 0; fi
  magick "$favicon[0]" -background none -alpha on -resize 64x64 -depth 8 -colors 4 -format '%c' histogram:info:- 2>/dev/null |
    nearest_brand
}

# Monorepos keep theirs deep (apps/client/public/favicon.png): a favicon beats an icon beats
# a logo, then the shallowest wins.
find_favicon() {
  git -C "$1" ls-files |
    awk '{ n = split($0, part, "/"); name = tolower(part[n]) }
      name ~ /^favicon\.(png|ico|svg)$/ { print 0, n, $0; next }
      name ~ /^icon\.(png|svg)$/        { print 1, n, $0; next }
      name ~ /^logo\.(png|svg)$/        { print 2, n, $0 }' |
    sort -n -k1,1 -k2,2 | head -n 1 | cut -d ' ' -f 3- | sed "s|^|$1/|"
}

# Reads ImageMagick's colour histogram: the most common colour that is neither see-through
# nor near gray, white or black picks the catppuccin colour with the closest hue.
nearest_brand() {
  awk -v hues="$brand_hues" '
    {
      count = $1 + 0
      split(substr($0, index($0, "(") + 1), channel, /[,)]/)
      r = channel[1]; g = channel[2]; b = channel[3]; a = channel[4]
      max = r; if (g > max) max = g; if (b > max) max = b
      min = r; if (g < min) min = g; if (b < min) min = b
      spread = max - min; lightness = (max + min) / 510
      saturation = spread == 0 ? 0 : spread / (255 - ((max + min - 255) < 0 ? 255 - max - min : max + min - 255))
      if (a < 128 || saturation < 0.25 || lightness < 0.15 || lightness > 0.85 || count <= best) next
      if (max == r) hue = 60 * ((g - b) / spread); else if (max == g) hue = 60 * ((b - r) / spread + 2); else hue = 60 * ((r - g) / spread + 4)
      if (hue < 0) hue += 360
      best = count; brand_hue = hue
    }
    END {
      if (best == 0) { printf "plain"; exit }
      n = split(hues, table, " "); closest = 360
      for (i = 1; i < n; i += 2) {
        distance = brand_hue - table[i + 1]; if (distance < 0) distance = -distance
        if (distance > 180) distance = 360 - distance
        if (distance < closest) { closest = distance; name = table[i] }
      }
      printf "%s", name
    }'
}

repository_key() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir
}

# cached KIND KEY MINUTES COMMAND...: COMMAND's output, kept for MINUTES. Written aside and
# moved in, so an overlapping run never reads a half-written answer.
cached() {
  local file=$state/$1/${2//\//_} minutes=$3
  shift 3
  if [[ -z $(find "$file" -mmin "-$minutes" 2>/dev/null) ]]; then
    mkdir -p "${file%/*}"
    "$@" > "$file.$$"
    mv "$file.$$" "$file"
  fi
  cat "$file"
}

case ${1:-} in
  rows) refresh_rows ;;
  rows-for) print_rows_for "$2" ;;
  *) report_everything ;;
esac
