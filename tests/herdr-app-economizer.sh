#!/usr/bin/env bash
# herdr-app's tree reads TokenEconomizer's `te status --json` for the focused folder: the sessions
# it learned from (its own and imported ones), the tools it took out and those waiting for
# `toolprune apply`. No row when te fails. Runs economizer.js in node with "herdr" stubbed.
set -euo pipefail
dotfiles=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-app-economizer.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

cat > "$scratch/herdr.mjs" <<'STUB'
export const home = () => "/Users/me";
export const exec = async (command, args) => globalThis.answer(command, args);
export const notify = (n) => { globalThis.notified = n; };
export const readTextFile = async (path) => globalThis.files[path] ?? null;
STUB
printf 'export const div = () => ({});\nexport const svg = () => ({});\nexport const h_flex = () => ({});\nexport const v_flex = () => ({});\n' > "$scratch/gpui.mjs"
cat > "$scratch/test.mjs" <<TEST
import { registerHooks } from "node:module";
import assert from "node:assert/strict";
const stubs = { herdr: "herdr.mjs", "gpui-kit": "gpui.mjs", "gpui-base": "gpui.mjs" };
registerHooks({
  resolve: (specifier, context, next) => stubs[specifier] ? { url: "file://$scratch/" + stubs[specifier], shortCircuit: true } : next(specifier, context),
});
const { askEconomizer, changePruning } = await import("$dotfiles/herdr-app/.config/herdr-app/mods/tree/economizer.js");
const status = {
  repo: "lastmile-lt/js", repo_root: "/p/js", state: "/state", warnings: [],
  config: { toolprune: "propose", toolprune_protect: ["mcp__claude-in-chrome__*"] },
  ledger: { sessions: 3, imported_sessions: 98 },
  toolprune: { applied: ["NotebookEdit"], proposal: [
    "CronCreate", "mcp__claude_ai_Google_Calendar__list_events", "mcp__claude_ai_Google_Calendar__get_event",
    "mcp__plugin_context-mode_context-mode__ctx_batch", "mcp__claude-in-chrome__navigate", "mcp__linear__delete_issue",
  ] },
};
let asked;
globalThis.files = {
  "/state/untool.json": JSON.stringify({ used_tools: ["Bash", "mcp__claude_ai_Google_Calendar__create_event"] }),
  "/p/js/.mcp.json": JSON.stringify({ mcpServers: { linear: {} } }),
};
globalThis.answer = (command, args) => { asked = [command, ...args]; return { code: 0, stdout: JSON.stringify(status), stderr: "" }; };
// The repository's own linear and the protected claude-in-chrome are never offered.
assert.deepEqual(await askEconomizer("/p/js"), {
  cwd: "/p/js", sessions: 101, protect: ["mcp__claude-in-chrome__*"],
  removedCount: 1, removed: [{ source: "built-in", prefix: null, tools: ["NotebookEdit"], used: 1 }],
  waitingCount: 4, waiting: [
    { source: "Google Calendar", prefix: "mcp__claude_ai_Google_Calendar__*", tools: ["mcp__claude_ai_Google_Calendar__list_events", "mcp__claude_ai_Google_Calendar__get_event"], used: 1 },
    { source: "built-in", prefix: null, tools: ["CronCreate"], used: 1 },
    { source: "context-mode", prefix: "mcp__plugin_context-mode_context-mode__*", tools: ["mcp__plugin_context-mode_context-mode__ctx_batch"], used: 0 },
  ],
  warnings: [],
});
assert.deepEqual(asked, ["/Users/me/.tokeneconomizer/bin/te", "status", "--json", "--cwd", "/p/js"]);
status.config.toolprune = "off";
assert.equal((await askEconomizer("/p/js")).waitingCount, 0);
await changePruning("/p/js", "apply", ["CronCreate", "mcp__linear__x"]);
assert.deepEqual(asked, ["/Users/me/.tokeneconomizer/bin/te", "toolprune", "apply", "CronCreate", "mcp__linear__x", "--cwd", "/p/js"]);
assert.equal(globalThis.notified.level, "success");
await changePruning("/p/js", "protect", ["mcp__a__*", "mcp__b__*"]);
assert.deepEqual(asked, ["/Users/me/.tokeneconomizer/bin/te", "config", "set", "toolprune_protect=mcp__a__*,mcp__b__*", "--cwd", "/p/js"]);
globalThis.answer = () => ({ code: 1, stdout: "", stderr: "no python3" });
await changePruning("/p/js", "restore", ["NotebookEdit"]);
assert.equal(globalThis.notified.level, "error");
assert.equal(await askEconomizer("/p/js"), null);
globalThis.answer = () => { throw new Error("te not installed"); };
assert.equal(await askEconomizer("/p/js"), null);
TEST
node "$scratch/test.mjs"
echo "herdr-app economizer tests passed: used tools per source, the repo's own and protected MCP servers never offered, nothing waits with pruning off, apply/protect/restore run te for the listed tools, no row when te fails."
