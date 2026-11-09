// herdr's sidebar (local-plugins/sidebar) in Herdr: the tree of spaces, worktrees and agents
// with the inbox and clauth's accounts below it, drawn as t3code's sidebar. Collapsing narrows it
// to a strip of space tiles instead of hiding it, so shift+up/down still walk it (tree.next / tree.previous).
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, spaces, focused, theme, nextCommand, setAgentOrder, keys, agents } from "herdr";
import { Git } from "./git.js";
import { buildTree, nextStop, latestAttention } from "./model.js";
import { spaceColor, publishSpaceColors } from "./colors.js";
import { askAccounts, accountsShelf } from "./accounts.js";
import { askCacheExpiries } from "./cache.js";

const EXPANDED_WIDTH = 280;
// The 20px icons with 11px either side.
const COLLAPSED_WIDTH = 42;
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
    this.cacheExpiries = {};
    this.refreshEachMinute(cx);
    cx.timer.every(60000, (cx) => this.refreshEachMinute(cx)); // also redraws the relative times
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
    return v_flex().id("tree-root").relative().size_full().bg(theme().chrome)
      .on_size_change((size, cx) => { this.width = size.width; cx.notify(); })
      .child(body)
      .child(foldingEdge(this));
  }

  refreshGit(cx, tree = buildTree(this.git, this.closedFolders)) {
    cx.spawn(async (cx) => {
      if (await this.git.refresh(tree.paths, tree.tops)) cx.notify();
    });
  }

  refreshEachMinute(cx) {
    cx.spawn(async (cx) => {
      this.cacheExpiries = await askCacheExpiries(agents());
      cx.notify();
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

// Double-clicking the divider folds or unfolds the sidebar elsewhere; the layout's divider takes
// no clicks from mods, so a strip along this side of it does.
function foldingEdge(view) {
  return div().id("tree-folding-edge").absolute().top(0).bottom(0).right(0).w(4).cursor_col_resize()
    .on_mouse_down("left", (event, cx) => {
      cx.stop_propagation();
      if (event.click_count === 2) view.toggle();
    });
}

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
  agent: (t, row, view) => agentRow(t, row, view.cacheExpiries[row.agent.address]),
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

// t3code's thread row: its status icon in the folder tile's column, where the collapsed sidebar
// draws it, then the title and its time over the checkout it works in.
function agentRow(t, row, cacheExpiresAt) {
  const { agent } = row;
  const recedes = agent.status === "idle" && !row.here;
  return rowSurface(t, row, h_flex().py(5).px(INSET).gap(10).items_center())
    .child(agentIcon(t, row))
    .child(v_flex().flex_1().min_w(0)
      .child(h_flex().h(22).gap(8).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(13)
          .text_color(recedes ? t.muted : t.foreground).when(!recedes, (d) => d.font_medium())
          .child(agentTitle(agent)))
        .when(agent.pinned, (el) => el.child(svg(`${ICONS}/pin.svg`).size(11).flex_none().text_color(t.dim)))
        .child(statusTime(t, agent, cacheExpiresAt)))
      .child(metaLine(t, row, agent.program)));
}

function agentIcon(t, row) {
  return h_flex().id(`tree-icon-${row.key}`).w(16).flex_none().justify_center()
    .tooltip(bubbleTooltip(row.agent))
    .child(BUBBLE_ICONS[row.agent.status](t, row.here));
}

// How long a working agent has worked, else how long an idle one has sat; the icon says the rest.
// A cache about to expire takes the slot: replying after it rewrites the whole context.
function statusTime(t, agent, cacheExpiresAt) {
  const expiring = minutesUntil(cacheExpiresAt);
  if (agent.status === "working") return div().flex_none().text_size(11.5).text_color(t.working).child(workingFor(agent));
  if (expiring !== null) return cacheMark(t, agent, expiring);
  if (agent.status === "idle") return div().flex_none().text_size(11.5).text_color(t.dim).child(sinceChange(agent));
  return div();
}

const CACHE_WARNING_MINUTES = 10;

// Whole minutes left within the warning window, else null.
function minutesUntil(expiresAt) {
  const left = Math.ceil(((expiresAt ?? 0) - Date.now()) / 60000);
  return left > 0 && left <= CACHE_WARNING_MINUTES ? left : null;
}

function cacheMark(t, agent, minutes) {
  return h_flex().id(`tree-cache-${agent.address}`).flex_none().gap(3).items_center().text_size(11.5).text_color(t.ansi3)
    .tooltip(`Prompt cache expires in ${minutes} min; a reply after that rewrites the whole context`)
    .child(svg(`${ICONS}/clock.svg`).size(11).text_color(t.ansi3))
    .child(div().child(`${minutes}m`));
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
    .when(Boolean(row.pullRequest?.checks), (el) => el.child(checksMark(t, row)))
    .when(Boolean(row.changes), (el) => el.child(changes(t, row)))
    .when(Boolean(program?.icon), (el) => el.child(svg(program.icon).size(12).flex_none().text_color(program.color ?? t.dim)));
}

function linkChip(t, id, label, color, url) {
  return div().id(id).flex_none().px(4).font_medium().text_color(color).cursor_pointer()
    .hover((s) => s.bg(t.hover))
    .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(url); })
    .child(label);
}

// Only checks that need a look show: failing ones as a red cross, running ones as a dim dot.
const CHECK_MARKS = {
  failing: { tooltip: "Checks failing", mark: (t) => div().text_color(t.ansi1).font_bold().child("✗") },
  running: { tooltip: "Checks running", mark: (t) => div().size(5).rounded(3).bg(t.dim) },
};

function checksMark(t, row) {
  const { checks, url } = row.pullRequest;
  return h_flex().id(`tree-checks-${row.key}`).flex_none().h(14).px(2).items_center().cursor_pointer()
    .hover((s) => s.bg(t.hover)).tooltip(CHECK_MARKS[checks].tooltip)
    .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(`${url}/checks`); })
    .child(CHECK_MARKS[checks].mark(t));
}

// A checkout's uncommitted changes, which open Reviewer on them: where they show is where to look.
function changes(t, row) {
  const { added, removed } = row.changes;
  return h_flex().id(`tree-changes-${row.key}`).flex_none().gap(3).px(3).cursor_pointer()
    .hover((s) => s.bg(t.hover)).tooltip(REVIEW_TOOLTIP)
    .on_click((_e, cx) => { cx.stop_propagation(); land(row); showReview(); })
    .child(div().text_color(t.ansi2).child(`+${added}`))
    .child(div().text_color(t.ansi1).child(`−${removed}`));
}

// The keys mod's prefix popup binds it (ctrl+\ r), which keys() can't see.
const REVIEW_TOOLTIP = "Review these changes in hunk  ⌃\\ r";

// Reviews open in hunk, in a pane beside the tab's (the keys mod's hunk-open).
function showReview() {
  run("keys.hunk-open");
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
  working: { label: "Working", color: "working", icon: null },
  blocked: { label: "Needs you", color: "blocked", icon: null },
  done: { label: "Done", color: "done", icon: "circle-check.svg" },
};

// A terminal's braille spinner lying flat, a raised block sliding along three cells, its frames
// swapped on the app's clock: an svg's spin() turns at about 30 fps, which visibly steps.
const SPINNER_FRAMES = ["⣤⣀⣀", "⣀⣤⣀", "⣀⣀⣤", "⣀⣤⣀"];
// An idle agent: the same cells, still and dim.
const SPINNER_AT_REST = "⣀⣀⣀";
// An agent waiting for you: braille's question sign (⠦) between resting cells, off for a beat.
const QUESTION_FRAMES = ["⣀⠦⣀", "⣀⠦⣀", "⣀⠦⣀", "⣀⣀⣀"];

function waitingQuestion(t, size) {
  return div().text_size(size).text_color(t.blocked).frames(QUESTION_FRAMES, 350);
}

function workingSpinner(t, size) {
  return div().text_size(size).text_color(t.working).frames(SPINNER_FRAMES, 140);
}

function statusSlot(t, agent) {
  const status = STATUS[agent.status];
  if (!status) return div().flex_none().text_size(11.5).text_color(t.dim).child(sinceChange(agent));
  const icon = agent.status === "working" ? workingSpinner(t, 10)
    : agent.status === "blocked" ? waitingQuestion(t, 10)
    : status.icon ? svg(`${ICONS}/${status.icon}`).size(11).text_color(t[status.color])
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

// herdr's compact sidebar: the expanded one's rows as one icon each, a project as its tile, an
// agent as its status, a worktree or checkout as a branch; every icon one size and the focused
// row lit full width.
function collapsedView(tree) {
  const t = theme();
  return v_flex().id("tree-collapsed").size_full().pt(4).pb(8).overflow_y_scrollbar()
    .children(tree.rows.filter((row) => COLLAPSED_ICONS[row.kind]).map((row) => collapsedRow(t, row)));
}

const COLLAPSED_ICON_SIZE = 20;

const COLLAPSED_ICONS = {
  folder: (t, row) => collapsedTile(t, row),
  agent: (t, row) => BUBBLE_ICONS[row.agent.status](t, row.here),
  checkout: (t, row) => svg(`${ICONS}/${row.worktree ? "git-branch" : "branch"}.svg`).size(16).text_color(lit(t, row.here)),
};

const COLLAPSED_TOOLTIPS = {
  folder: (row) => row.space.name,
  agent: (row) => bubbleTooltip(row.agent),
  checkout: (row) => (row.branch ? `${row.name} · ${row.branch}` : row.name),
};

function collapsedRow(t, row) {
  return h_flex().id(`tree-collapsed-${row.key}`).w_full().h(28).flex_none().items_center().justify_center().cursor_pointer()
    .when(row.kind === "folder", (el) => el.mt(8))
    .tooltip(COLLAPSED_TOOLTIPS[row.kind](row))
    .when(row.here, (el) => el.bg(t.selected))
    .hover((s) => s.bg(t.hover))
    .on_click(() => land(row))
    .child(h_flex().size(COLLAPSED_ICON_SIZE).items_center().justify_center().child(COLLAPSED_ICONS[row.kind](t, row)));
}

// A closed folder hides its agents, so its tile carries the most urgent of them as a corner dot.
function collapsedTile(t, folder) {
  return div().relative()
    .child(spaceTile(t, folder.space, COLLAPSED_ICON_SIZE))
    .when(Boolean(folder.dot), (el) => el.child(
      div().absolute().right(-3).top(-3).size(8).rounded(4).border(2).border_color(t.chrome).bg(t[STATUS[folder.dot]?.color])));
}

function bubbleTooltip(agent) {
  const status = STATUS[agent.status];
  return status ? `${agentTitle(agent)} · ${status.label}` : agentTitle(agent);
}

// The row you're on lights its icon, as its background; a status colour stays its own.
function lit(t, here) {
  return here ? t.foreground : t.dim;
}

const BUBBLE_ICONS = {
  working: (t) => workingSpinner(t, 11),
  blocked: (t) => waitingQuestion(t, 11),
  done: (t) => svg(`${ICONS}/circle-check.svg`).size(16).text_color(t.done),
  idle: (t, here) => div().text_size(11).text_color(lit(t, here)).child(SPINNER_AT_REST),
};

function spaceTile(t, space, size) {
  return h_flex().size(size).flex_none().bg(spaceColor(t, space)).items_center().justify_center()
    .text_size(size * 0.55).font_bold().text_color("#ffffff").child([...space.name][0]?.toUpperCase() ?? "?");
}

// A label with its shortcut as bound now (keys.json), e.g. "Settings  ⌘,"; herdr's old status bar
// read the palette key the same way. Mods can't share files, so the tree, tab bar and top row each
// keep a copy.
const KEY_GLYPHS = { cmd: "⌘", ctrl: "⌃", shift: "⇧", alt: "⌥", option: "⌥" };

function withKey(label, action) {
  const bound = keys().find((k) => k.action === action);
  if (!bound) return label;
  const parts = bound.keys.endsWith("--") ? [...bound.keys.slice(0, -2).split("-"), "-"] : bound.keys.split("-");
  return `${label}  ${parts.map((p) => KEY_GLYPHS[p] ?? p.toUpperCase()).join("")}`;
}
