// herdr's sidebar (local-plugins/sidebar) in Herdr: the tree of spaces, worktrees and agents
// with the inbox and clauth's accounts below it, drawn as t3code's sidebar. Collapsing narrows it
// to a strip of space tiles instead of hiding it, so shift+up/down still walk it (tree.next / tree.previous).
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, spaces, focused, theme, nextCommand, setAgentOrder, keys, agents, openOverlay } from "herdr";
import { Git, ticketOf } from "./git.js";
import { buildTree, nextStop, latestAttention } from "./model.js";
import { spaceColor, publishSpaceColors } from "./colors.js";
import { askAccounts, accountsShelf } from "./accounts.js";
import { askCacheExpiries } from "./cache.js";
import { askDone, doneShelf } from "./done.js";
import { askPorts } from "./ports.js";
import { askEconomizer, economizerShelf, changePruning } from "./economizer.js";

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
    this.done = [];
    this.ports = {};
    this.doneOpen = false;
    this.refreshEachMinute(cx);
    cx.timer.every(60000, (cx) => this.refreshEachMinute(cx)); // also redraws the relative times
    this.accounts = [];
    this.accountsOpen = false;
    this.refreshAccounts(cx);
    cx.timer.every(30000, (cx) => this.refreshAccounts(cx));
    this.economizer = null;
    this.economizerCwd = null;
    this.economizerOpen = false;
    cx.timer.every(60000, (cx) => this.refreshEconomizer(cx, focused()?.cwd));
    cx.spawn(async (cx) => this.receiveCommands(cx));
  }

  render(cx) {
    const tree = buildTree(this.git, this.closedFolders);
    this.refreshGit(cx, tree);
    if (focused()?.cwd !== this.economizerCwd) this.refreshEconomizer(cx, focused()?.cwd);
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
      const tops = buildTree(this.git, this.closedFolders).tops.filter((c) => !c.machine).map((c) => c.top);
      [this.cacheExpiries, this.done, this.ports] = await Promise.all([askCacheExpiries(agents()), askDone(), askPorts(tops)]);
      cx.notify();
    });
  }

  refreshAccounts(cx) {
    cx.spawn(async (cx) => {
      this.accounts = await askAccounts();
      cx.notify();
    });
  }

  // Asked again when the focus moves to another folder, and each minute for what sessions changed.
  refreshEconomizer(cx, cwd) {
    this.economizerCwd = cwd;
    if (!cwd) return;
    cx.spawn(async (cx) => {
      const economizer = await askEconomizer(cwd);
      if (cwd !== this.economizerCwd) return; // the focus moved on while te answered
      this.economizer = economizer;
      cx.notify();
    });
  }

  changePruning(cx, cwd, action, items) {
    cx.spawn(async (cx) => {
      await changePruning(cwd, action, items);
      this.economizer = await askEconomizer(cwd);
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
    .when(view.done.length > 0, (el) => el.child(doneShelf(t, view.done, view.doneOpen, (_e, cx) => { view.doneOpen = !view.doneOpen; cx.notify(); }, ICONS)))
    .when(view.economizer !== null, (el) => el.child(economizerShelf(t, view.economizer, view.economizerOpen, (_e, cx) => { view.economizerOpen = !view.economizerOpen; cx.notify(); }, (cx, cwd, action, items) => view.changePruning(cx, cwd, action, items))))
    .when(view.accounts.length > 0, (el) => el.child(accountsShelf(t, view.accounts, view.accountsOpen, (_e, cx) => { view.accountsOpen = !view.accountsOpen; cx.notify(); })));
}

function withPorts(row, view) {
  return { ...row, ports: view.ports[row.top] ?? [] };
}

const ROW_VIEWS = {
  folder: (t, row, view) => folderRow(t, row, view),
  agent: (t, row, view) => agentRow(t, withPorts(row, view), view.cacheExpiries[row.agent.address]),
  checkout: (t, row, view) => checkoutRow(t, withPorts(row, view)),
};

// t3code's project folder: a shelf header with a chevron and its checkout's commits ahead of and
// behind main; closed, it counts what it hides and shows the most urgent of them as a dot.
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
    .when(Boolean(row.drift), (el) => el.child(driftMark(t, row)))
    .when(Boolean(row.dot), (el) => el.child(div().size(6).flex_none().rounded(3).bg(t[STATUS[row.dot].color])))
    .when(row.hiddenCount > 0, (el) => el.child(div().flex_none().text_size(11.5).text_color(t.dim).child(String(row.hiddenCount))))
    .child(h_flex().id(`tree-chevron-${row.space.id}`).size(20).flex_none().rounded(4).items_center().justify_center()
      .hover((s) => s.bg(t.input)).on_click(toggle)
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
        .child(div().id(`tree-title-${row.key}`).flex_1().min_w(0).truncate().text_size(13)
          .text_color(recedes ? t.muted : t.foreground).when(!recedes, (d) => d.font_medium())
          .tooltip(`${agentTitle(agent)} · ${row.spaceName} › ${agent.tab_name}`)
          .child(withoutTicket(agentTitle(agent), row.branch)))
        .when(agent.pinned, (el) => el.child(svg(`${ICONS}/pin.svg`).size(11).flex_none().text_color(t.dim)))
        .child(statusTime(t, agent, cacheExpiresAt)))
      .child(metaLine(t, row)));
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
  if (agent.status === "working") return timer(t, agent, t.working, "Working since", tabOf(agent)?.working_since, workingFor(agent));
  if (expiring !== null) return cacheMark(t, agent, expiring);
  if (agent.status === "idle") return timer(t, agent, t.dim, "Idle since", tabOf(agent)?.changed_at, sinceChange(agent));
  return div();
}

// A time with the clock time it counts from on hover: "Working since 14:32".
function timer(t, agent, color, label, since, text) {
  return div().id(`tree-time-${agent.address}`).flex_none().text_size(11.5).text_color(color)
    .when(Boolean(since), (el) => el.tooltip(`${label} ${clockTime(since)}`))
    .child(text);
}

// 14:32 today, else "Nov 8 14:32".
function clockTime(at) {
  const date = new Date(at);
  const time = `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
  if (date.toDateString() === new Date().toDateString()) return time;
  return `${MONTHS[date.getMonth()]} ${date.getDate()} ${time}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

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
    .child(metaLine(t, row));
}

function card(t, row) {
  // Titles line up with the folder's name, past its 16px tile.
  return rowSurface(t, row, v_flex().py(5).pl(INSET + 16 + 10).pr(INSET).justify_center());
}

// The second line: one name for the work (its ticket, else its branch's last segment) and, on
// the right, icons whose colour says the state and whose hover says the detail: the pull request,
// uncommitted changes, and a globe when its servers listen on ports.
function metaLine(t, row) {
  return h_flex().h(18).gap(8).items_center().text_size(11.5).text_color(t.dim)
    .child(svg(`${ICONS}/${row.worktree ? "git-branch" : "branch"}.svg`).size(11).flex_none())
    .child(workName(t, row))
    .child(h_flex().flex_none().gap(1).mr(-4)
      .when(Boolean(row.pullRequest), (el) => el.child(pullRequestMark(t, row)))
      .when(Boolean(row.changes), (el) => el.child(changesMark(t, row)))
      .when(row.ports.length > 0, (el) => el.child(portsMark(t, row))));
}

// An icon's hit box: wider than the icon and lit on hover. Themes paint hover, selected and border
// alike, so the row's own hover hides them; input is a step lighter. The trailing -4px margin lines
// the last icon up with the time above.
function iconButton(t, id, tooltip) {
  return h_flex().id(id).size(18).flex_none().rounded(4).items_center().justify_center().cursor_pointer()
    .hover((s) => s.bg(t.input)).tooltip(tooltip);
}

// Text lit the same way; its padding is pulled back out so the text stays where it was.
function textButton(t, id, tooltip) {
  return h_flex().id(id).h(18).px(4).mx(-4).rounded(4).items_center().cursor_pointer()
    .hover((s) => s.bg(t.input)).tooltip(tooltip);
}

// The ticket opens its Linear issue when the pull request links one, else a click copies the
// branch. Only the text takes the click; the space after it still lands on the row.
function workName(t, row) {
  const line = h_flex().flex_1().min_w(0);
  if (!row.branch) return line.child(div().truncate().child("no branch"));
  const issue = row.pullRequest?.issue;
  const name = (tooltip) => textButton(t, `tree-name-${row.key}`, tooltip).min_w(0).text_color(t.muted)
    .child(div().truncate().child(ticketOf(row.branch)));
  if (issue) return line.child(name(`${row.branch} · open ${issue.id} in Linear`).on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(issue.url); }));
  return line.child(name(`${row.branch} · click to copy`).on_click((_e, cx) => { cx.stop_propagation(); cx.write_to_clipboard(row.branch); }));
}

// One icon in its state's colour, red while checks fail; it opens where the pull request is
// reviewed: Linear's review when the repo is wired to it, else GitHub.
function pullRequestMark(t, row) {
  const { number, state, url, review, checks } = row.pullRequest;
  const color = checks === "failing" ? t.ansi1 : t[PULL_REQUEST_COLORS[state]] ?? t.dim;
  const facts = [`#${number} ${state}`, checks ? `checks ${checks}` : null, `open in ${review ? "Linear" : "GitHub"}`];
  return iconButton(t, `tree-pr-${row.key}`, facts.filter(Boolean).join(" · "))
    .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(review ?? url); })
    .child(svg("mods/tree/git-pull-request.svg").size(11).text_color(color));
}

// ↑3 ↓12 as herdr's git_status, each side only when it has commits: ahead of main, behind it.
// A click opens lazygit in the space, as ctrl+\ g does there.
function driftMark(t, row) {
  const { ahead, behind } = row.drift;
  const sides = [ahead ? `↑${ahead}` : null, behind ? `↓${behind}` : null].filter(Boolean);
  const facts = [ahead ? `${ahead} ahead of main` : null, behind ? `${behind} behind` : null, "as of the last fetch", LAZYGIT_TOOLTIP];
  return textButton(t, `tree-drift-${row.key}`, facts.filter(Boolean).join(" · ")).flex_none().text_size(11.5).text_color(t.muted)
    .on_click((_e, cx) => { cx.stop_propagation(); land(row); run("keys.lazygit"); })
    .child(sides.join(" "));
}

const LAZYGIT_TOOLTIP = "lazygit  ⌃\\ g";

// One globe however many ports; a click lists them at the pointer (the ports mod, sized by its
// 31px rows and 5px padding), each opening on localhost.
function portsMark(t, row) {
  return iconButton(t, `tree-ports-${row.key}`, `Listening on ${row.ports.map((p) => `:${p.port}`).join(" ")}`)
    .on_click((_e, cx) => { cx.stop_propagation(); openOverlay({ mod: "ports", kind: "popup", width: 240, height: row.ports.length * 31 + 10, props: { ports: row.ports } }); })
    .child(svg("mods/tree/globe.svg").size(11).text_color(t.muted));
}

// Uncommitted changes as an amber dot, counted on hover; a click opens Reviewer on them.
function changesMark(t, row) {
  const { added, removed } = row.changes;
  return iconButton(t, `tree-changes-${row.key}`, `+${added} −${removed} · ${REVIEW_TOOLTIP}`)
    .on_click((_e, cx) => { cx.stop_propagation(); land(row); showReview(); })
    .child(div().size(6).rounded(3).bg(t.ansi3));
}

// The keys mod's prefix popup binds it (ctrl+\ r), which keys() can't see.
const REVIEW_TOOLTIP = "review in hunk  ⌃\\ r";

// Reviews open in hunk, in a pane beside the tab's (the keys mod's hunk-open).
function showReview() {
  run("keys.hunk-open");
}

// "ENG-3957 per-product sends" over a branch on ENG-3957 reads "per-product sends": the line
// below names the ticket.
function withoutTicket(title, branch) {
  const ticket = branch ? ticketOf(branch) : "";
  const lead = title.match(/^([A-Za-z]+-\d+)\b[\s:·-]*(.+)/);
  return lead && lead[1].toUpperCase() === ticket ? lead[2] : title;
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
    .child(div().h(18).truncate().text_size(11.5).text_color(t.dim).child(`${row.spaceName} · ${agent.tab_name}`));
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
