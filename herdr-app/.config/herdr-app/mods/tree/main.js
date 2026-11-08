// herdr's sidebar (local-plugins/sidebar) in Herdr: the tree of spaces, worktrees and agents
// with the inbox and clauth's accounts below it, drawn as t3code's sidebar. Collapsing narrows it
// to a strip of space tiles instead of hiding it, so shift+up/down still walk it (tree.next / tree.previous).
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, spaces, focused, theme, nextCommand, setAgentOrder } from "herdr";
import { Git } from "./git.js";
import { buildTree, nextStop, latestAttention } from "./model.js";
import { spaceColor, publishSpaceColors } from "./colors.js";
import { askAccounts, accountsShelf } from "./accounts.js";

const EXPANDED_WIDTH = 280;
const COLLAPSED_WIDTH = 64;
// Every row's text and icons start and end this far from the sidebar's edges, as its footer's.
const INSET = 16;
const ICONS = "mods/workspace-chrome";

export default class Tree extends View {
  init(_props, cx) {
    this.git = new Git();
    this.width = EXPANDED_WIDTH;
    this.cursor = null;
    this.inboxOpen = true;
    this.closedFolders = new Set();
    cx.timer.every(15000, (cx) => this.refreshGit(cx));
    cx.timer.every(60000, (cx) => cx.notify()); // relative times
    this.accounts = [];
    this.accountsOpen = false;
    this.refreshAccounts(cx);
    cx.timer.every(30000, (cx) => this.refreshAccounts(cx));
    cx.spawn(async (cx) => this.receiveCommands(cx));
  }

  render(cx) {
    const tree = buildTree(this.git, this.closedFolders);
    this.refreshGit(cx, tree);
    publishSpaceColors(theme(), tree.folderOf);
    setAgentOrder([...tree.inbox, ...tree.rows.filter((r) => r.kind === "agent")].map((r) => r.agent.address));
    const body = this.width < 120 ? collapsedView(tree) : expandedView(tree, this);
    return v_flex().id("tree-root").size_full().bg(theme().chrome)
      .on_size_change((size, cx) => { this.width = size.width; cx.notify(); })
      .child(body);
  }

  refreshGit(cx, tree = buildTree(this.git, this.closedFolders)) {
    cx.spawn(async (cx) => {
      if (await this.git.refresh(tree.paths, tree.tops)) cx.notify();
    });
  }

  refreshAccounts(cx) {
    cx.spawn(async (cx) => {
      this.accounts = await askAccounts();
      cx.notify();
    });
  }

  async receiveCommands(cx) {
    for (;;) {
      const command = await nextCommand();
      TREE_COMMANDS[command]?.(this);
      cx.notify();
    }
  }

  toggle() {
    run("layout.resize", { id: "sidebar", px: this.width < 120 ? EXPANDED_WIDTH : COLLAPSED_WIDTH });
  }

  // A press saves where it landed; when the focus has since moved some other way, the next
  // press starts from wherever the focus is now. Walking only the inbox skips the tree.
  walk(step, inboxOnly) {
    const tree = buildTree(this.git, this.closedFolders);
    const walked = inboxOnly ? { ...tree, rows: [] } : tree;
    const cursor = this.cursor?.pane === focused()?.pane && (!inboxOnly || this.cursor.inbox) ? this.cursor : null;
    const row = nextStop(walked, cursor, step);
    if (!row) return;
    land(row);
    const inbox = row.kind === "inbox" ? cursor?.inbox ?? tree.inbox : null;
    this.cursor = { key: row.key, pane: focused()?.pane, inbox };
  }

  jumpToAttention() {
    const row = latestAttention(buildTree(this.git, this.closedFolders));
    if (row) land(row);
  }
}

// What keys.json sends this mod: shift+up/down walk the tree and inbox, ctrl+shift+j/k the inbox
// alone, as herdr's agent panel, and ctrl+shift+i goes to whoever most recently wants you.
const TREE_COMMANDS = {
  toggle: (view) => view.toggle(),
  next: (view) => view.walk(1, false),
  previous: (view) => view.walk(-1, false),
  "inbox-next": (view) => view.walk(1, true),
  "inbox-previous": (view) => view.walk(-1, true),
  attention: (view) => view.jumpToAttention(),
};

function land(row) {
  if (row.target.terminal) run("agent.focus", { terminal: row.target.terminal });
  else if (row.target.pane) run("pane.focus", { pane: row.target.pane });
  else run("space.select", { id: row.target.space });
}

function expandedView(tree, view) {
  const t = theme();
  return v_flex().size_full().min_h(0)
    .child(v_flex().id("tree-rows").flex_1().min_h(0).pb(6).gap(1).overflow_y_scrollbar()
      .children(tree.rows.map((row) => ROW_VIEWS[row.kind](t, row, view))))
    .when(tree.inbox.length > 0, (el) => el.child(inbox(t, tree.inbox, view)))
    .when(view.accounts.length > 0, (el) => el.child(accountsShelf(t, view.accounts, view.accountsOpen, (_e, cx) => { view.accountsOpen = !view.accountsOpen; cx.notify(); })));
}

const ROW_VIEWS = {
  folder: (t, row, view) => folderRow(t, row, view),
  agent: (t, row) => agentRow(t, row),
  checkout: (t, row) => checkoutRow(t, row),
};

// t3code's project folder: a shelf header with a chevron; closed, it counts what it hides and
// shows the most urgent of them as a dot.
function folderRow(t, row, view) {
  const toggle = (_e, cx) => {
    cx.stop_propagation();
    if (row.closed) view.closedFolders.delete(row.space.id);
    else view.closedFolders.add(row.space.id);
    cx.notify();
  };
  return rowSurface(t, row, h_flex().h(32).mt(8).pl(INSET).pr(INSET - 4).gap(10).items_center())
    .child(spaceTile(t, row.space, 16))
    .child(div().flex_1().min_w(0).truncate().text_size(13.5).font_medium()
      .text_color(row.focused ? t.foreground : t.muted).child(row.space.name))
    .when(Boolean(row.dot), (el) => el.child(div().size(6).flex_none().rounded(3).bg(t[STATUS[row.dot].color])))
    .when(row.hiddenCount > 0, (el) => el.child(div().flex_none().text_size(11.5).text_color(t.dim).child(String(row.hiddenCount))))
    .child(h_flex().id(`tree-chevron-${row.space.id}`).size(20).flex_none().items_center().justify_center()
      .hover((s) => s.bg(t.hover)).on_click(toggle)
      .child(svg(`${ICONS}/${row.closed ? "chevron-right" : "chevron-down"}.svg`).size(12).text_color(t.dim)));
}

// t3code's thread row: the title and its status, then the checkout it works in.
function agentRow(t, row) {
  const { agent } = row;
  const recedes = agent.status === "idle" && !row.here;
  return card(t, row)
    .child(h_flex().h(22).gap(8).items_center()
      .child(div().flex_1().min_w(0).truncate().text_size(13)
        .text_color(recedes ? t.muted : t.foreground).when(!recedes, (d) => d.font_medium())
        .child(agentTitle(agent)))
      .when(agent.pinned, (el) => el.child(svg(`${ICONS}/pin.svg`).size(11).flex_none().text_color(t.dim)))
      .child(statusSlot(t, agent)))
    .child(metaLine(t, row, agent.program));
}

// A checkout nobody's agent works in: a worktree space, or a folder a shell is in.
function checkoutRow(t, row) {
  return card(t, row)
    .child(h_flex().h(22).gap(8).items_center()
      .child(div().flex_1().min_w(0).truncate().text_size(13)
        .text_color(row.focused ? t.foreground : t.muted).when(row.focused, (d) => d.font_medium())
        .child(row.name)))
    .child(metaLine(t, row, null));
}

function card(t, row) {
  // Titles line up with the folder's name, past its 16px tile.
  return rowSurface(t, row, v_flex().py(5).pl(INSET + 16 + 10).pr(INSET).justify_center());
}

// The second line: worktree or branch icon and the branch, the Linear issue and pull request
// (each opens in the browser), the uncommitted changes, and the program's icon.
function metaLine(t, row, program) {
  return h_flex().h(18).gap(6).items_center().text_size(11.5).text_color(t.dim)
    .child(svg(`${ICONS}/${row.worktree ? "git-branch" : "branch"}.svg`).size(11).flex_none())
    .child(div().flex_1().min_w(0).truncate().child(row.branch ?? "no branch"))
    .when(Boolean(row.pullRequest?.issue), (el) => el.child(linkChip(t, `tree-issue-${row.key}`, row.pullRequest.issue.id, t.muted, row.pullRequest.issue.url)))
    .when(Boolean(row.pullRequest), (el) => el.child(linkChip(t, `tree-pr-${row.key}`, `#${row.pullRequest.number}`, t[PULL_REQUEST_COLORS[row.pullRequest.state]] ?? t.dim, row.pullRequest.url)))
    .when(Boolean(row.changes), (el) => el.child(changes(t, row.changes)))
    .when(Boolean(program?.icon), (el) => el.child(svg(program.icon).size(12).flex_none().text_color(program.color ?? t.dim)));
}

function linkChip(t, id, label, color, url) {
  return div().id(id).flex_none().px(4).font_medium().text_color(color).cursor_pointer()
    .hover((s) => s.bg(t.hover))
    .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(url); })
    .child(label);
}

function changes(t, { added, removed }) {
  return h_flex().flex_none().gap(3)
    .child(div().text_color(t.ansi2).child(`+${added}`))
    .child(div().text_color(t.ansi1).child(`−${removed}`));
}

function agentTitle(agent) {
  return agent.title || agent.program?.name || "agent";
}

// The inbox as t3code's shelves: a header with a count that folds it.
function inbox(t, rows, view) {
  const head = h_flex().id("tree-inbox-head").h(32).flex_none().px(INSET).gap(8).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
    .on_click((_e, cx) => { view.inboxOpen = !view.inboxOpen; cx.notify(); })
    .child(div().flex_1().text_size(12).font_medium().text_color(t.dim).child("Inbox"))
    .child(div().text_size(11.5).text_color(t.dim).child(String(rows.length)))
    .child(svg(`${ICONS}/${view.inboxOpen ? "chevron-down" : "chevron-right"}.svg`).size(12).text_color(t.dim));
  return v_flex().flex_none().max_h(320).border_t(1).border_color(t.border)
    .child(head)
    .when(view.inboxOpen, (el) => el.child(v_flex().id("tree-inbox").flex_none().h(inboxHeight(rows)).gap(1).overflow_y_scrollbar()
      .children(rows.map((row) => inboxCard(t, row)))));
}

// A scrolling list takes no height from its rows, so it's given theirs, up to five cards.
const INBOX_CARD_HEIGHT = 50;

function inboxHeight(rows) {
  return Math.min(5, rows.length) * (INBOX_CARD_HEIGHT + 1);
}

function inboxCard(t, row) {
  const { agent } = row;
  return rowSurface(t, row, v_flex().h(INBOX_CARD_HEIGHT).px(INSET).justify_center())
    .child(h_flex().h(22).gap(8).items_center()
      .child(div().flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground).child(agentTitle(agent)))
      .when(agent.pinned, (el) => el.child(svg(`${ICONS}/pin.svg`).size(11).flex_none().text_color(t.dim)))
      .child(statusSlot(t, agent)))
    .child(div().h(18).truncate().text_size(11.5).text_color(t.dim).child(`${agent.space_name} · ${agent.tab_name}`));
}

// One row's surface: hover, the focused row's highlight, and a click that lands on it.
function rowSurface(t, row, element) {
  return element.id(`tree-${row.key}`).flex_none().cursor_pointer()
    .when(row.here, (el) => el.bg(t.selected))
    .hover((s) => s.bg(t.hover))
    .on_click(() => land(row));
}

// t3code's status slot: what needs a look as its icon in its colour (the word on hover), with how
// long a working one has worked; else how long since anything changed.
const STATUS = {
  working: { label: "Working", color: "working", icon: "spinner.svg" },
  blocked: { label: "Needs you", color: "blocked", icon: null },
  done: { label: "Done", color: "done", icon: "circle-check.svg" },
};

function statusSlot(t, agent) {
  const status = STATUS[agent.status];
  if (!status) return div().flex_none().text_size(11.5).text_color(t.dim).child(sinceChange(agent));
  const icon = status.icon
    ? svg(`${ICONS}/${status.icon}`).size(11).text_color(t[status.color]).when(agent.status === "working", (s) => s.spin(900))
    : div().size(6).rounded(3).bg(t[status.color]);
  return h_flex().id(`tree-status-${agent.address}`).flex_none().gap(4).items_center().text_size(11.5).text_color(t[status.color])
    .tooltip(status.label)
    .child(icon)
    .when(agent.status === "working", (el) => el.child(div().child(workingFor(agent))));
}

// t3code's working timer, to the minute: the minute tick redraws it without a timer of its own.
function workingFor(agent) {
  const since = tabOf(agent)?.working_since;
  if (!since) return "";
  return Date.now() - since < 60000 ? "<1m" : age(since);
}

function sinceChange(agent) {
  const changedAt = tabOf(agent)?.changed_at;
  return changedAt ? age(changedAt) : "";
}

function tabOf(agent) {
  return spaces().flatMap((s) => s.tabs).find((x) => x.id === agent.tab);
}

function age(since) {
  const minutes = Math.floor((Date.now() - since) / 60000);
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}h`;
  return `${Math.floor(minutes / (60 * 24))}d`;
}

const PULL_REQUEST_COLORS = { open: "ansi2", draft: "dim", merged: "ansi5", closed: "ansi1" };

// herdr's compact sidebar: a tile a space, its most urgent agent as a dot.
function collapsedView(tree) {
  const t = theme();
  const tiles = tree.rows.filter((r) => r.kind === "folder").map((row) =>
    div().id(`tree-tile-${row.space.id}`).relative().p(3).cursor_pointer()
      .when(row.focused, (el) => el.bg(t.selected))
      .hover((s) => s.bg(t.hover))
      .on_click(() => land(row))
      .child(spaceTile(t, row.space, 28))
      .when(Boolean(STATUS[row.space.status]), (el) => el.child(
        div().absolute().right(0).top(0).size(9).rounded(5).border(2).border_color(t.chrome).bg(t[STATUS[row.space.status]?.color]))));
  return v_flex().size_full().items_center().pt(8).gap(4).overflow_y_scrollbar().children(tiles);
}

function spaceTile(t, space, size) {
  return h_flex().size(size).flex_none().bg(spaceColor(t, space)).items_center().justify_center()
    .text_size(size * 0.55).font_bold().text_color("#ffffff").child([...space.name][0]?.toUpperCase() ?? "?");
}
