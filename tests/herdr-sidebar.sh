#!/usr/bin/env bash
# The sidebar plugin, linked into a temporary server. Each space draws a tree: its agents, then
# a row for every other checkout its panes are in, with that checkout's ticket and pull request
# and its agents under it, and a pointer on the row the focus is on. Every agent carries its
# branch's ticket, its project's name under its favicon's colour, and its title, dimmed once
# its reply is read. Why an agent waits is read from its transcript. A project with no
# favicon keeps a colour no other project has. gh is a stub; git and
# ImageMagick are real.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-sidebar.XXXXXX)
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
case "$3" in
  feature/eng-8-main-work) echo 'open #8' ;;
  feature/side) echo 'draft #7' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$scratch/bin/gh"
git init -q -b feature/eng-8-main-work "$scratch/app"
# Pickitoo's violet, kept as deep as a monorepo keeps it.
mkdir -p "$scratch/app/apps/web/public"
magick -size 16x16 xc:'#8E7BFE' "$scratch/app/apps/web/public/favicon.png"
git -C "$scratch/app" add apps
git -C "$scratch/app" -c user.name=test -c user.email=test@example.com commit -q -m init
git -C "$scratch/app" worktree add -q -b feature/side "$scratch/app-side"
git -C "$scratch/app" worktree add -q -b feature/eng-77-wide "$scratch/app-wide"
mkdir -p "$scratch/notes"
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

# app: an agent in the main checkout, a shell beside it, and an agent in its linked worktree.
# notes: no Git at all.
app=$(herdr workspace create --cwd "$scratch/app" --label app | jq -er '.result.root_pane.pane_id')
side=$(herdr pane split "$app" --direction right --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
shell=$(herdr pane split "$app" --direction down --cwd "$scratch/app" | jq -er '.result.pane.pane_id')
notes=$(herdr workspace create --cwd "$scratch/notes" --label notes | jq -er '.result.root_pane.pane_id')
agent_state() { herdr pane report-agent "$1" --source custom:test --agent claude --state "$2" >/dev/null; }
for pane in "$app" "$side" "$notes"; do agent_state "$pane" idle; done

agent_tokens() { herdr agent list | jq -c --arg pane "$1" '.result.agents[] | select(.pane_id == $pane) | .tokens // {}'; }
workspace_tokens() { herdr workspace list | jq -c --arg label "$1" '.result.workspaces[] | select(.label == $label) | .tokens // {}'; }
# wait_for WANT COMMAND...: runs are asynchronous, so poll until COMMAND prints WANT.
wait_for() {
  local want=$1 got
  shift
  for ((i=0;i<100;i++)); do
    got=$("$@")
    [[ $got != "$want" ]] || return 0
    sleep 0.1
  done
  echo "$*: expected $want, got $got" >&2
  herdr plugin log list | jq -r '.result.logs[] | select(.plugin_id == "sidebar" and .status == "failed") | .stderr' | tail -n 5 >&2
  exit 1
}
wait_for '{"project_mauve":"app","ticket":"ENG-8"}' agent_tokens "$app"
wait_for '{"project_mauve":"app","ticket":"side"}' agent_tokens "$side"
# notes has no favicon, so it draws any colour app's mauve left free.
notes_colour() { agent_tokens "$notes" | jq -r 'keys | map(select(startswith("project_"))) | join(",")'; }
notes_colour_is_free() { notes_colour | sed -E 's/^project_(red|peach|green|teal|blue)$/free/'; }
wait_for free notes_colour_is_free
drawn=$(notes_colour)

# The tree: app's own agent, then the worktree, its ticket left out where its folder already
# says it, its draft's number, and its agent. The pointer takes the focused agent's glyph, and
# the worktree it is in takes a heavy line. Both leave the tree when the focus is on the shell,
# where herdr's own space name shows it.
focus() {
  jq -cn --arg pane "$1" '{id: "test", method: "pane.focus", params: {pane_id: $pane}}' |
    /usr/bin/nc -U -w 1 "$HERDR_SOCKET_PATH" | head -n 1 | jq -e '.result' >/dev/null
}
tree_rows() { workspace_tokens app | jq -c 'with_entries(select(.key | test("^(ticket|pr_|row_)")))'; }
blank=$'\u2800'
focus "$side"
wait_for "$(jq -cn --arg blank "$blank" '{pr_open: "#8", row_1: "○",
  row_2: "┕━ app-side", row_2_pr_draft: "#7", row_3: "\($blank) ▸", ticket: "ENG-8"}')" tree_rows
focus "$shell"
wait_for "$(jq -cn --arg blank "$blank" '{pr_open: "#8", row_1: "○",
  row_2: "└─ app-side", row_2_pr_draft: "#7", row_3: "\($blank) ○", ticket: "ENG-8"}')" tree_rows

# A branch with no pull request clears the old number; a status change starts the next run.
# Working draws the agent's glyph.
git -C "$scratch/app-side" checkout -q -b fix/eng-9-other
agent_state "$side" working
wait_for '{"project_mauve":"app","ticket":"ENG-9"}' agent_tokens "$side"
wait_for "$(jq -cn --arg blank "$blank" '{pr_open: "#8", row_1: "○",
  row_2: "└─ app-side · ENG-9", row_3: "\($blank) ●", ticket: "ENG-8"}')" tree_rows
# A shell in the worktree puts the pointer on the worktree's own row.
side_shell=$(herdr pane split "$side" --direction down --cwd "$scratch/app-side" | jq -er '.result.pane.pane_id')
focus "$side_shell"
row_2() { workspace_tokens app | jq -r '.row_2'; }
wait_for '└▸ app-side · ENG-9' row_2

# A worktree opened as its own space, which herdr nests under app and indents: its one agent's
# title goes on the space's own row, with no rows under it, and the space goes by its ticket
# rather than its whole branch, to leave the title room.
wide=$(herdr worktree open --cwd "$scratch/app" --path "$scratch/app-wide" | jq -er '.result.root_pane.pane_id')
cat > "$scratch/wide-title.sh" <<'TITLE'
printf '\033]2;%s\007' 'Widen the sidebar'
TITLE
herdr pane run "$wide" "sh $scratch/wide-title.sh" >/dev/null
agent_state "$wide" idle
wide_rows() { herdr workspace list | jq -c --arg pane "$wide" '.result.workspaces[] | select(.workspace_id == ($pane | split(":")[0])) | .tokens // {} | with_entries(select(.key | test("^(ticket|lead_|row_|name)")))'; }
wait_for '{"lead_idle":"Widen the sidebar","name":"ENG-77"}' wide_rows

# A title longer than the 80 characters herdr keeps: bright while the agent works, dimmed once
# it is idle and seen.
long_title='Investigate the connect ingest throughput regression across every partition and replica'
kept='Investigate the connect ingest throughput regression across every partition and'
cat > "$scratch/title.sh" <<TITLE
printf '\033]2;%s\007' '$long_title'
TITLE
herdr pane run "$app" "sh $scratch/title.sh" >/dev/null
agent_state "$app" working
wait_for "{\"project_mauve\":\"app\",\"ticket\":\"ENG-8\",\"title_active\":\"$kept\"}" agent_tokens "$app"
# Finished out of sight, it is done and its reply unread: its row says so and is cut to
# herdr's 80 characters too.
focus "$notes"
agent_state "$app" idle
unread_tokens="{\"project_mauve\":\"app\",\"ticket\":\"ENG-8\",\"title_active\":\"$kept\",\"unread\":\"✓\"}"
wait_for "$unread_tokens" agent_tokens "$app"
row_1() { workspace_tokens app | jq -r '.row_1'; }
# Each space is named by the plugin, bold only while the focus is in it.
names() { workspace_tokens "$1" | jq -c '{name, name_focused}'; }
wait_for '{"name":"app","name_focused":null}' names app
wait_for '{"name":null,"name_focused":"notes"}' names notes
done_row=$(jq -rn --arg row "✓ $long_title" '$row | .[0:80] | sub("\\s+$"; "")')
wait_for "$done_row" row_1
# A glance ends herdr's done but not the unread reply; marking it read dims the title.
herdr agent focus "$app" >/dev/null
focus "$notes"
wait_for "$done_row" row_1
wait_for "$unread_tokens" agent_tokens "$app"
herdr agent focus "$app" >/dev/null
herdr plugin action invoke sidebar.acknowledge >/dev/null
wait_for "{\"project_mauve\":\"app\",\"ticket\":\"ENG-8\",\"title_idle\":\"$kept\"}" agent_tokens "$app"

# Pinning the focused agent gives it the first pin and a pushpin before its title, cut to the
# same 80 characters; pinning it again takes both away.
pinned_title=$(jq -rn --arg title $'\xef\x90\xb5'" $long_title" '$title | .[0:80] | sub("\\s+$"; "")')
herdr plugin action invoke sidebar.pin >/dev/null
wait_for "$(jq -cn --arg title "$pinned_title" '{pin: "0001", project_mauve: "app", ticket: "ENG-8", title_idle: $title}')" agent_tokens "$app"
herdr plugin action invoke sidebar.pin >/dev/null
wait_for "{\"project_mauve\":\"app\",\"ticket\":\"ENG-8\",\"title_idle\":\"$kept\"}" agent_tokens "$app"

[[ $(notes_colour) == "$drawn" ]] || { echo "notes changed colour: $drawn to $(notes_colour)" >&2; exit 1; }

# Why an agent waits, from its Claude transcript: the last line of a reply, bare of markdown,
# or the command a blocked agent asks to run. Herdr keeps a session id only for an agent it
# detected itself, so this reads sample transcripts directly. A line still being written is
# passed over.
reason() { printf '%s\n' "$@" | jq -nRr -f "$repo/herdr/.config/herdr/local-plugins/sidebar/scripts/reason.jq"; }
expect_reason() {
  local want=$1 got
  shift
  got=$(reason "$@")
  [[ $got == "$want" ]] || { echo "reason: expected $want, got $got" >&2; exit 1; }
}
expect_reason 'Shall I ship it?' \
  '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Ask first."}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"I made the change.\n\n- **Shall   I ship it?**\n"}]}}' \
  '{"type":"system","subtype":"turn_duration"}' '{"type":"assistant","mess'
expect_reason 'Bash: git push' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Pushing now."},{"type":"tool_use","name":"Bash","input":{"command":"git push\necho pushed"}}]}}'
expect_reason 'Ship it now?' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Ship it now?"}]}}]}}'

# Every run, including the inbox view request, succeeds, and reporting tokens must not
# set off another round of hooks.
sidebar_runs() { herdr plugin log list | jq '[.result.logs[] | select(.plugin_id == "sidebar")]'; }
for ((i=0;i<100;i++)); do
  sidebar_runs | jq -e 'all(.[]; .status != "running")' >/dev/null && break
  sleep 0.1
done
sidebar_runs | jq -e 'all(.[]; .status == "succeeded")' >/dev/null ||
  { sidebar_runs | jq -c 'first(.[] | select(.status != "succeeded"))' >&2; exit 1; }
runs=$(sidebar_runs | jq length)
sleep 2
[[ $(sidebar_runs | jq length) == "$runs" ]] || { echo 'sidebar hooks keep running' >&2; exit 1; }
printf '%s\n' 'sidebar plugin passed: tree rows with worktrees, tickets, pull request states and the focus marker, favicon colours, titles bright until read, unread replies and why agents wait, pin and unpin, sticky free colours, inbox view accepted'
