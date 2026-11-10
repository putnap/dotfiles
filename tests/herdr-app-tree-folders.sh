#!/usr/bin/env bash
# herdr-app's tree (mods/tree/model.js) groups spaces into one folder per repository: a space
# whose shell cd'd from a worktree back into the main checkout nests in the main space's folder
# with a row of its own, and a worktree space is drawn once, not under every main-checkout space.
# Rows on the main checkout come first, before the main space's agent working in a worktree.
# A worktree space's own row lands on its shell, not on whichever of its panes was last focused.
# Runs the model in node with the "herdr" module stubbed by the spaces and panes below.
set -euo pipefail
dotfiles=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-app-tree.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

cat > "$scratch/herdr.mjs" <<'STUB'
const state = globalThis.herdrState;
export const spaces = () => state.spaces;
export const panes = () => state.panes;
export const agents = () => state.agents;
export const focused = () => null;
export const exec = async () => ({ code: 1, stdout: "", stderr: "" });
STUB
cat > "$scratch/test.mjs" <<TEST
import { registerHooks } from "node:module";
registerHooks({
  resolve: (specifier, context, next) => specifier === "herdr" ? { url: "file://$scratch/herdr.mjs", shortCircuit: true } : next(specifier, context),
});
const js = "/p/js", goLive = "/p/js-go-live", refactor = "/p/js-refactor", unmakaronin = "/p/js-unmakaronin", review = "/p/js-review";
const space = (id, folder, tab) => ({ id, name: id, named: false, folder, machine: null, tabs: [{ id: tab }] });
globalThis.herdrState = {
  // main: a shell in js and an agent in the refactor worktree; goLive: made in js-go-live, its shell now in js; wt: a worktree's agent.
  spaces: [space("main", js, "t-main"), space("goLive", goLive, "t-go"), space("wt", unmakaronin, "t-wt"), space("review", review, "t-rv")],
  panes: [
    { pane: "p0", tab: "t-main", terminal: "t0", cwd: js },
    { pane: "p1", tab: "t-main", terminal: "t1", cwd: refactor },
    { pane: "p2", tab: "t-go", terminal: "t2", cwd: js },
    { pane: "p3", tab: "t-wt", terminal: "t3", cwd: unmakaronin },
    { pane: "p4", tab: "t-rv", terminal: "t4", cwd: review },
    { pane: "p5", tab: "t-rv", terminal: "t5", cwd: refactor },
  ],
  agents: [
    { address: "t1", pane: "p1", space: "main", status: "working", seq: 1 },
    { address: "t3", pane: "p3", space: "wt", status: "working", seq: 2 },
    { address: "t5", pane: "p5", space: "review", status: "working", seq: 3 },
  ],
};
const checkouts = {
  [js]: { top: js, repo: js, linked: false, branch: "main" },
  [refactor]: { top: refactor, repo: js, linked: true, branch: "refactor" },
  [goLive]: { top: goLive, repo: js, linked: true, branch: "go-live" },
  [unmakaronin]: { top: unmakaronin, repo: js, linked: true, branch: "unmakaronin" },
  [review]: { top: review, repo: js, linked: true, branch: "review" },
};
const git = { checkout: (_m, folder) => checkouts[folder] ?? null, pullRequest: () => null };
const { buildTree } = await import("$dotfiles/herdr-app/.config/herdr-app/mods/tree/model.js");
const tree = buildTree(git, new Set());
const rows = tree.rows.map((r) => r.kind === "agent" ? "agent " + r.agent.address : r.kind + " " + (r.space?.id ?? r.name));
const want = ["folder main", "checkout main", "agent t1", "agent t3", "checkout review", "agent t5"];
if (JSON.stringify(rows) !== JSON.stringify(want)) {
  console.error("FAIL: rows were", rows, "wanted", want);
  process.exit(1);
}
const reviewTarget = tree.rows.find((r) => r.key === "checkout:review").target;
if (reviewTarget.pane !== "p4") {
  console.error("FAIL: the review worktree's row lands on", reviewTarget, "wanted its shell p4");
  process.exit(1);
}
console.log("ok herdr-app tree folders");
TEST
node "$scratch/test.mjs"
