// TokenEconomizer for the focused pane's repository, above clauth's accounts: the never-used tools it
// proposes to take out of Claude here and those it took, per source (built-in, or each MCP server)
// beside how many of that source's tools were used. Servers the repository's own .mcp.json brings,
// and protected ones, are never offered. Each row prunes, protects or restores just its own tools.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, home, notify, readTextFile } from "herdr";

const GROUP_HEIGHT = 22;

// What each button asks te to do, and the toast once it has.
const ACTIONS = {
  apply: { args: (items) => ["toolprune", "apply", ...items], done: "Taken out of Claude from its next session here" },
  restore: { args: (items) => ["toolprune", "restore", ...items], done: "Given back to Claude from its next session here" },
  protect: { args: (items) => ["config", "set", `toolprune_protect=${items.join(",")}`], done: "Never proposed here again" },
};

// What `te status` says about cwd's repository; null when te isn't installed or can't tell.
export async function askEconomizer(cwd) {
  try {
    const r = await exec(te(), ["status", "--json", "--cwd", cwd]);
    if (r.code !== 0) return null;
    const status = JSON.parse(r.stdout);
    const [used, repoServers] = await Promise.all([askUsedTools(status.state), askRepoServers(status.repo_root)]);
    return economizer(cwd, status, used, repoServers);
  } catch {
    return null;
  }
}

// Runs one of ACTIONS for cwd's repository with the tools (or protect patterns) it acts on.
export async function changePruning(cwd, action, items) {
  const r = await exec(te(), [...ACTIONS[action].args(items), "--cwd", cwd]);
  if (r.code !== 0) notify({ title: `TokenEconomizer ${action} failed`, body: r.stderr || r.stdout, level: "error" });
  else notify({ title: ACTIONS[action].done, level: "success" });
}

// Counts only when there is something: yellow ones wait for you, red means te warns.
export function economizerShelf(t, e, open, toggle, change) {
  const unfoldable = e.removedCount + e.waitingCount > 0;
  const head = h_flex().id("tree-economizer-head").h(28).flex_none().px(16).gap(10).items_center().text_size(12)
    .tooltip(e.warnings.length > 0 ? e.warnings.join("\n") : `Learned from ${e.sessions} sessions`)
    .when(unfoldable, (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)).on_click(toggle))
    .child(div().flex_1().min_w(0).truncate().text_color(e.warnings.length > 0 ? t.ansi1 : t.dim).child("TokenEconomizer"))
    .when(e.removedCount > 0, (el) => el.child(count(t, "mods/tree/scissors.svg", e.removedCount, t.dim)))
    .when(e.waitingCount > 0, (el) => el.child(count(t, "mods/workspace-chrome/clock.svg", e.waitingCount, t.ansi3)))
    .when(unfoldable, (el) => el.child(svg(`mods/workspace-chrome/${open ? "chevron-down" : "chevron-right"}.svg`).size(12).text_color(t.dim)));
  const act = (action, items) => (cx) => change(cx, e.cwd, action, items);
  return v_flex().flex_none().border_t(1).border_color(t.border)
    .child(head)
    .when(open && unfoldable, (el) => el.child(details(t, e, act)));
}

// With pruning off, te still keeps the list it last proposed; nothing will act on it. A protect
// pattern only leaves te's list at the next fold, so it is filtered here at once.
function economizer(cwd, status, used, repoServers) {
  const protect = status.config.toolprune_protect;
  const hidden = [...protect, ...repoServers.map((server) => `mcp__${server}__*`)];
  const proposal = status.config.toolprune === "off" ? [] : status.toolprune.proposal;
  const waiting = proposal.filter((tool) => !hidden.some((pattern) => matches(tool, pattern)));
  const removed = status.toolprune.applied;
  return {
    cwd,
    sessions: status.ledger.sessions + status.ledger.imported_sessions,
    protect,
    removedCount: removed.length,
    removed: groupBySource(removed, used),
    waitingCount: waiting.length,
    waiting: groupBySource(waiting, used),
    warnings: status.warnings,
  };
}

// `te status` doesn't say which tools were used, so they come from its own state file.
async function askUsedTools(state) {
  const text = await readTextFile(`${state}/untool.json`);
  return text === null ? [] : JSON.parse(text).used_tools ?? [];
}

// The MCP servers the repository itself brings: whoever works in it is meant to have them.
async function askRepoServers(repoRoot) {
  const text = await readTextFile(`${repoRoot}/.mcp.json`);
  return text === null ? [] : Object.keys(JSON.parse(text).mcpServers ?? {});
}

// te matches protect patterns with fnmatch; its `*` is all anyone writes.
function matches(tool, pattern) {
  const escaped = pattern.split("*").map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"));
  return new RegExp(`^${escaped.join(".*")}$`).test(tool);
}

function count(t, icon, n, color) {
  return h_flex().flex_none().gap(4).items_center().text_color(color)
    .child(svg(icon).size(11).text_color(color))
    .child(String(n));
}

function details(t, e, act) {
  const all = (groups) => groups.flatMap((g) => g.tools);
  return v_flex().id("tree-economizer").flex_none().pb(6).max_h(12 * GROUP_HEIGHT).overflow_y_scrollbar()
    .when(e.waitingCount > 0, (el) => el.child(section(t, "Never used here",
      [actionButton(t, "head-apply", "scissors.svg", "Take all of these out of Claude here", act("apply", all(e.waiting)))],
      e.waiting.map((g) => groupRow(t, "waiting", g, [
        ...(g.prefix ? [actionButton(t, `protect-${g.source}`, "shield.svg", `Never propose ${g.source} here`, act("protect", [...e.protect, g.prefix]))] : []),
        actionButton(t, `apply-${g.source}`, "scissors.svg", `Take ${g.source}'s unused tools out of Claude here`, act("apply", g.tools)),
      ])))))
    .when(e.removedCount > 0, (el) => el.child(section(t, "Taken out",
      [actionButton(t, "head-restore", "undo-2.svg", "Give all of these back to Claude here", act("restore", all(e.removed)))],
      e.removed.map((g) => groupRow(t, "removed", g, [
        actionButton(t, `restore-${g.source}`, "undo-2.svg", `Give ${g.source}'s tools back to Claude here`, act("restore", g.tools)),
      ])))));
}

function section(t, title, buttons, rows) {
  return v_flex()
    .child(h_flex().h(GROUP_HEIGHT + 2).pl(16).pr(11).gap(2).items_center().text_size(11).text_color(t.dim)
      .child(div().flex_1().child(title))
      .children(buttons))
    .children(rows);
}

// 17/84 used: of linear's tools in Claude here, how many a session ever called.
function groupRow(t, kind, g, buttons) {
  return h_flex().id(`tree-economizer-${kind}-${g.source}`).h(GROUP_HEIGHT).pl(28).pr(11).gap(2).items_center().text_size(12)
    .hover((s) => s.bg(t.hover)).tooltip(g.tools.map((tool) => sourceOf(tool).name).join("\n"))
    .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(g.source))
    .child(div().flex_none().whitespace_nowrap().text_color(t.dim).mr(4).child(`${g.used}/${g.used + g.tools.length} used`))
    .children(buttons);
}

function actionButton(t, id, icon, tooltip, act) {
  return h_flex().id(`tree-economizer-${id}`).size(18).flex_none().rounded(4).items_center().justify_center().cursor_pointer()
    .hover((s) => s.bg(t.input)).tooltip(tooltip)
    .on_click((_e, cx) => { cx.stop_propagation(); act(cx); })
    .child(svg(`mods/tree/${icon}`).size(11).text_color(t.muted));
}

// Largest group first, with how many of its source's tools were used; `prefix` protects an MCP server.
function groupBySource(tools, used) {
  const groups = new Map();
  for (const tool of tools) {
    const { source } = sourceOf(tool);
    groups.set(source, [...(groups.get(source) ?? []), tool]);
  }
  const usedSources = used.map((tool) => sourceOf(tool).source);
  return [...groups]
    .map(([source, members]) => ({ source, prefix: sourceOf(members[0]).prefix, tools: members, used: usedSources.filter((s) => s === source).length }))
    .sort((a, b) => b.tools.length - a.tools.length);
}

// mcp__claude_ai_Google_Calendar__list_events → Google Calendar; mcp__plugin_context-mode_context-mode__ctx_batch → context-mode.
function sourceOf(tool) {
  const match = /^mcp__(.+?)__(.+)$/.exec(tool);
  if (!match) return { source: "built-in", name: tool, prefix: null };
  const server = match[1].replace(/^claude_ai_/, "").replace(/^plugin_[^_]+_/, "").replaceAll("_", " ");
  return { source: server, name: match[2], prefix: `mcp__${match[1]}__*` };
}

// The plugin keeps this link pointing at its current install.
function te() {
  return `${home()}/.tokeneconomizer/bin/te`;
}
