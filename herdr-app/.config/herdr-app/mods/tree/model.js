// The sidebar's rows, drawn and walked in one order, as t3code's project folders: each space a
// folder, a repository's worktree spaces inside its main checkout's. In a folder, its agents, each
// with its checkout's branch, pull request and changes; a checkout with no agent (a worktree space,
// or other checkout a pane is in) gets one row of its own. Below, the inbox: pinned agents, then
// blocked and done ones, newest first.
import { spaces, panes, agents, focused } from "herdr";
import { ticketOf } from "./git.js";

// { rows, inbox, paths, tops, folderOf }: paths and tops are what git and gh are asked about;
// folderOf says which space's folder each space is drawn in (a worktree space, its repository's).
export function buildTree(git, closedFolders) {
  const here = focused();
  const allSpaces = spaces();
  const spaceOfTab = Object.fromEntries(allSpaces.flatMap((s) => s.tabs.map((t) => [t.id, s])));
  const allPanes = panes().filter((p) => p.terminal && spaceOfTab[p.tab]);
  const agentOfPane = Object.fromEntries(agents().map((a) => [a.pane, a]));
  const checkoutOf = (p) => git.checkout(spaceOfTab[p.tab].machine, p.cwd);

  const trees = allSpaces.map((shown) => {
    const own = allPanes.filter((p) => spaceOfTab[p.tab].id === shown.id);
    const checkout = homeCheckout(git.checkout(shown.machine, shown.folder), own.map(checkoutOf));
    const space = { ...shown, name: spaceName(shown, checkout) };
    const inHome = (p) => !checkoutOf(p) || checkoutOf(p).top === checkout?.top;
    const others = [...new Set(own.filter((p) => !inHome(p)).map((p) => checkoutOf(p).top))];
    return {
      space, checkout,
      home: own.filter(inHome),
      groups: others.map((top) => ({ top, checkout: checkoutOf(own.find((p) => checkoutOf(p)?.top === top)), panes: own.filter((p) => checkoutOf(p)?.top === top) })),
    };
  });

  const nameOf = Object.fromEntries(trees.map((tree) => [tree.space.id, tree.space.name]));
  const context = { here, agentOfPane, git, nameOf };
  const folders = projectFolders(trees);
  return {
    rows: folders.flatMap((folder) => folderRows(folder, closedFolders.has(folder.owner.space.id), context)),
    folderOf: Object.fromEntries(folders.flatMap((f) => [f.owner, ...f.worktrees].map((tree) => [tree.space.id, f.owner.space]))),
    inbox: inboxRows(here, nameOf),
    paths: [...allPanes.map((p) => ({ machine: spaceOfTab[p.tab].machine, folder: p.cwd })), ...allSpaces.map((s) => ({ machine: s.machine, folder: s.folder }))].filter((f) => f.folder),
    tops: trees.flatMap((t) => [t.checkout, ...t.groups.map((g) => g.checkout)].filter(Boolean).map((c) => ({ machine: t.space.machine, top: c.top }))),
  };
}

// A space is its folder's checkout while any of its panes is still in it, so an agent moving into
// a worktree doesn't take the space along; else its first pane's (the folder has been left).
function homeCheckout(folderCheckout, paneCheckouts) {
  if (folderCheckout && paneCheckouts.some((c) => c?.top === folderCheckout.top)) return folderCheckout;
  return paneCheckouts[0] ?? folderCheckout;
}

// herdr-app calls an unnamed space after where its first terminal is, which an agent moving into
// a worktree changes; after its home checkout's folder instead, it stays put.
function spaceName(space, checkout) {
  return space.named || !checkout ? space.name : checkout.top.split("/").pop();
}

// Where shift+down (step 1) or shift+up (-1) lands: the next stop after where the walk last
// landed, or after the row the focus is on when it has moved since; through the tree, then the
// inbox as it was on entering it, then round to the top.
export function nextStop(tree, cursor, step) {
  const list = [...tree.rows, ...(cursor?.inbox ?? tree.inbox)];
  const found = list.findIndex((r) => (cursor ? r.key === cursor.key : r.here));
  const from = found !== -1 ? found : step > 0 ? -1 : list.length;
  for (let i = 1; i <= list.length; i++) {
    const row = list[wrap(from + step * i, list.length)];
    if (row.stop) return row;
  }
  return null;
}

// herdr's attention.jump: the agent that most recently came to need you, blocked or done.
export function latestAttention(tree) {
  const waiting = tree.inbox.filter((r) => r.agent.status === "blocked" || r.agent.status === "done");
  return waiting.reduce((latest, r) => (latest && latest.agent.seq > r.agent.seq ? latest : r), null);
}

function wrap(index, length) {
  return ((index % length) + length) % length;
}

// herdr nests a repository's linked worktrees in its main checkout's space, but only for a
// repository with both open; every other space is a folder of its own. One folder per repository:
// a second space on the main checkout (a shell cd'd back into it) nests in the first one's too.
function projectFolders(trees) {
  const ownerOf = repoOwners(trees);
  const folderOf = (t) => (t.checkout ? ownerOf.get(t.checkout.repo) : null) ?? t;
  return trees.filter((t) => folderOf(t) === t).map((owner) => ({
    owner,
    worktrees: trees.filter((t) => t !== owner && folderOf(t) === owner),
  }));
}

// Each repository's first space on its main checkout.
function repoOwners(trees) {
  const owners = new Map();
  for (const t of trees) {
    if (t.checkout && !t.checkout.linked && !owners.has(t.checkout.repo)) owners.set(t.checkout.repo, t);
  }
  return owners;
}

// A closed folder hides its rows, says how many agents it hides and the most urgent one's
// status, and is itself the stop; so is an open folder with nothing in it.
// Inside, the main checkout's rows come first, then the worktrees'.
function folderRows({ owner, worktrees }, closed, context) {
  const onMain = worktrees.filter((tree) => !tree.checkout?.linked);
  const onWorktrees = worktrees.filter((tree) => tree.checkout?.linked);
  const inside = [
    ...homeEntries(owner, true, context),
    ...onMain.flatMap((tree) => spaceEntries(tree, false, context)),
    ...groupEntries(owner, context),
    ...onWorktrees.flatMap((tree) => spaceEntries(tree, false, context)),
  ];
  const hiddenAgents = closed ? inside.filter((r) => r.kind === "agent").map((r) => r.agent) : [];
  const header = {
    kind: "folder", key: `space:${owner.space.id}`, space: owner.space,
    drift: owner.checkout?.drift ?? null,
    stop: closed || inside.length === 0, closed,
    hiddenCount: hiddenAgents.length,
    dot: mostUrgent(hiddenAgents),
    here: owner.home.some((p) => p.pane === context.here?.pane && !p.status),
    focused: [owner, ...worktrees].some((t) => t.space.id === context.here?.space),
    target: { space: owner.space.id },
  };
  return [header, ...(closed ? [] : inside)];
}

// A space's agents, its own checkout's first, then each other checkout's; a checkout without
// agents is a row itself, except the folder's own, which its header stands for.
function spaceEntries(tree, ownsFolder, context) {
  return [...homeEntries(tree, ownsFolder, context), ...groupEntries(tree, context)];
}

function homeEntries(tree, ownsFolder, context) {
  const home = checkoutEntries(tree.home, tree.checkout, context);
  return home.length > 0 || ownsFolder ? home : [checkoutRow(`checkout:${tree.space.id}`, worktreeName(tree), tree.checkout, tree.space, tree.home, { space: tree.space.id }, context)];
}

function groupEntries(tree, context) {
  return tree.groups.flatMap((group) => {
    const rows = checkoutEntries(group.panes, group.checkout, context);
    if (rows.length > 0) return rows;
    const shell = group.panes.find((p) => !p.status) ?? group.panes[0];
    return [checkoutRow(`checkout:${tree.space.id}:${group.top}`, group.top.split("/").pop(), group.checkout, tree.space, group.panes, { pane: shell.pane }, context)];
  });
}

function checkoutEntries(list, checkout, { here, agentOfPane, git, nameOf }) {
  return list.filter((p) => agentOfPane[p.pane]).map((p) => {
    const agent = agentOfPane[p.pane];
    return { kind: "agent", key: `agent:${agent.address}`, stop: true, agent, spaceName: nameOf[agent.space], ...checkoutFacts(checkout, agent.space, git), here: agent.pane === here?.pane, target: { terminal: agent.address } };
  });
}

function checkoutRow(key, name, checkout, space, list, target, { here, git }) {
  return {
    kind: "checkout", key, stop: true, name, ...checkoutFacts(checkout, space.id, git),
    here: list.some((p) => p.pane === here?.pane && !p.status),
    focused: list.some((p) => p.pane === here?.pane),
    target,
  };
}

// What a row's second line says: the branch, whether it's a linked worktree, its pull request
// (with the Linear issue it links) and its uncommitted changes.
function checkoutFacts(checkout, spaceId, git) {
  const machine = spaces().find((s) => s.id === spaceId)?.machine ?? null;
  return {
    top: machine ? null : checkout?.top ?? null, // ports are read on this machine only
    branch: checkout?.branch ?? null,
    worktree: Boolean(checkout?.linked),
    changes: checkout?.changes ?? null,
    pullRequest: checkout ? git.pullRequest(machine, checkout.top) : null,
  };
}

// A worktree space is named by its ticket: "ENG-4818" says more than its folder's name.
function worktreeName(tree) {
  return ticketOf(tree.checkout?.branch) || tree.space.name;
}

const URGENCY = ["blocked", "working", "done"];

function mostUrgent(list) {
  return URGENCY.find((status) => list.some((a) => a.status === status)) ?? null;
}

function inboxRows(here, nameOf) {
  const waiting = agents().filter((a) => a.pinned || a.status === "blocked" || a.status === "done");
  waiting.sort((a, b) => (b.pinned - a.pinned) || (b.seq - a.seq));
  return waiting.map((agent) => ({ kind: "inbox", key: `inbox:${agent.address}`, stop: true, agent, spaceName: nameOf[agent.space] ?? agent.space_name, here: agent.pane === here?.pane, target: { terminal: agent.address } }));
}
