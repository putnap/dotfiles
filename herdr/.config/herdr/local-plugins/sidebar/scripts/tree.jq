# The sidebar's tree, which report.sh draws and navigate.sh walks, so both keep one order.
# Spaces come in herdr's sidebar order. Under each are its agents in the space's own checkout,
# then a group for every other checkout its panes are in (a worktree opened in a tab), each
# with its agents. Panes keep their tab order. `here` marks the one row the focus is on: the
# focused agent, or else the space or group whose shell, nvim or other pane has the focus. A
# group is `active`, and a space `focused`, while the focus is on any of its panes.
# `drawn` is the space's tokens as herdr has them now. `target` is the pane a row opens: a
# space or group's first pane that runs no agent, or for a space without one, the pane herdr
# would show on switching to it.
#
# A module (include "tree"): tree($checkouts) takes herdr's snapshot, $checkouts being
# {folder: its git checkout, "" outside Git} for every pane folder and every worktree herdr knows
# a space by, and gives {spaces: [...], inbox: [...]}, the inbox being what the Agents panel lists.
# new_folders($checkouts) gives the folders $checkouts has no answer for yet.

def distinct: reduce .[] as $item ([]; if any(.[]; . == $item) then . else . + [$item] end);

def first_shell($panes): first($panes[] | select(.agent == null) | .pane_id) // null;

# herdr lists a repository's linked worktrees straight after its main checkout, nested under
# it, but only for a repository with both open; every other space keeps its own place.
def sidebar_order:
  . as $workspaces
  | def key_of($linked): [$workspaces[] | .worktree | select(. != null and .is_linked_worktree == $linked) | .repo_key];
  (key_of(true) - (key_of(true) - key_of(false))) as $grouped
  | reduce $workspaces[] as $workspace ({emitted: [], order: []};
      ($workspace.worktree.repo_key // null) as $key
      | if $key == null or ($key | IN($grouped[]) | not) then .order += [$workspace]
        elif any(.emitted[]; . == $key) then .
        else .emitted += [$key]
          | .order += [$workspaces[] | select(.worktree.repo_key == $key and .worktree.is_linked_worktree == false)]
          | .order += [$workspaces[] | select(.worktree.repo_key == $key and .worktree.is_linked_worktree == true) | . + {nested: true}]
        end)
  | .order;

# workspace.move requests that make herdr's own order, which its collapsed sidebar draws, the
# tree's: walked from the top, each space out of place moves up into place.
def space_moves:
  [.workspaces[].workspace_id] as $current
  | [.workspaces | sidebar_order[] | .workspace_id] as $wanted
  | reduce range(0; $wanted | length) as $at ({order: $current, moves: []};
      if .order[$at] == $wanted[$at] then .
      else (.order - [$wanted[$at]]) as $rest
        | .order = $rest[:$at] + [$wanted[$at]] + $rest[$at:]
        | .moves += [{id: "sidebar:order", method: "workspace.move", params: {workspace_id: $wanted[$at], insert_index: $at}}]
      end)
  | .moves;

# An agent whose reply is still unread (report.sh's $unread) stays done once seen.
def shown_status:
  if .agent_status == "idle" and (.tokens.unread // "") != "" then "done" else .agent_status end;

def agent_row($focused):
  {pane_id, status: (.agent | shown_status), title: (.agent.terminal_title_stripped // ""),
   here: (.pane_id == $focused)};

def shell_focused($panes; $focused): any($panes[]; .pane_id == $focused and .agent == null);

def group($workspace_id; $panes; $focused; $is_last):
  .checkout as $checkout
  | [$panes[] | select(.checkout == $checkout)] as $own
  | {workspace_id: $workspace_id, checkout: $checkout, name: ($checkout | split("/") | last), last: $is_last,
     here: shell_focused($own; $focused), active: any($own[]; .pane_id == $focused), target: first_shell($own),
     agents: [$own[] | select(.agent != null) | agent_row($focused)]};

def space($panes; $focused; $shown; $checkouts):
  .workspace_id as $id
  | [$panes[] | select(.workspace_id == $id)] as $own
  | (.worktree.checkout_path as $path | if $path then $checkouts[$path] // $path else $own[0].checkout // "" end) as $main
  | [$own[] | select(.checkout == "" or .checkout == $main)] as $home
  | ([$own[] | .checkout | select(. != "" and . != $main)] | distinct) as $others
  | {workspace_id: $id, label: (.label // ""), checkout: $main, nested: (.nested // false), drawn: (.tokens // {}),
     focused: any($own[]; .pane_id == $focused), here: shell_focused($home; $focused), target: (first_shell($home) // $shown[$id]),
     agents: [$home[] | select(.agent != null) | agent_row($focused)],
     groups: [$others | to_entries[] | (.key == (($others | length) - 1)) as $last
       | {checkout: .value} | group($id; $own; $focused; $last)]};

# Pinned agents in pin order, then blocked, done and unread ones newest first: report.sh's agent view.
def inbox:
  [.agents[] | select(shown_status == "blocked" or shown_status == "done" or .tokens.pin != null)]
  | sort_by([(.tokens.pin // "~"), -.state_change_seq]) | map(.pane_id);

def tree($checkouts):
  (.focused_pane_id // "") as $focused
  | (.agents | map({(.pane_id): .}) | add // {}) as $agents
  | (.tabs | to_entries | map({(.value.tab_id): .key}) | add // {}) as $tab_order
  | (.layouts | map({(.tab_id): .focused_pane_id}) | add // {}) as $tab_focus
  | (.workspaces | map({(.workspace_id): $tab_focus[.active_tab_id]}) | add // {}) as $shown
  | [.panes | to_entries | sort_by([$tab_order[.value.tab_id], .key])[] | .value
     | . + {checkout: ($checkouts[.foreground_cwd // .cwd // ""] // ""), agent: $agents[.pane_id]}] as $panes
  | {spaces: [.workspaces | sidebar_order[] | space($panes; $focused; $shown; $checkouts)], inbox: inbox};

def new_folders($checkouts):
  [(.panes[] | .foreground_cwd // .cwd), (.workspaces[] | .worktree.checkout_path) | values | select($checkouts[.] == null)]
  | unique;
