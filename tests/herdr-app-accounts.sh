#!/usr/bin/env bash
# herdr-app's tree lists the Claude accounts behind papulab's CLIProxyAPI: each one's 5h and week
# usage, asked through the proxy, and which one new sessions go to. Runs accounts.js in node with
# "herdr" and fetch stubbed.
set -euo pipefail
dotfiles=$(cd "$(dirname "$0")/.." && pwd -P)
scratch=$(mktemp -d /tmp/herdr-app-accounts.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/home/.cli-proxy-api"
echo "mgmt-key" > "$scratch/home/.cli-proxy-api/management-key"
echo "export const home = () => \"$scratch/home\";" > "$scratch/herdr.mjs"
printf 'export const div = () => ({});\nexport const svg = () => ({});\nexport const h_flex = () => ({});\nexport const v_flex = () => ({});\n' > "$scratch/gpui.mjs"
cat > "$scratch/test.mjs" <<TEST
import { registerHooks } from "node:module";
import assert from "node:assert/strict";
const stubs = { herdr: "herdr.mjs", "gpui-kit": "gpui.mjs", "gpui-base": "gpui.mjs" };
registerHooks({
  resolve: (specifier, context, next) => stubs[specifier] ? { url: "file://$scratch/" + stubs[specifier], shortCircuit: true } : next(specifier, context),
});
const fresh = async () => (await import("$dotfiles/herdr-app/.config/herdr-app/mods/tree/accounts.js?" + Math.random())).askAccounts;

const credential = (label, index, extra = {}) => ({ provider: "claude", label, auth_index: index, disabled: false, quota_blocked: false, cooldowns: [], ...extra });
const usage = (fiveHours, week, fable) => ({
  five_hour: { utilization: fiveHours, resets_at: "2030-01-01T10:00:00Z" },
  seven_day: { utilization: week, resets_at: "2030-01-05T10:00:00Z" },
  limits: [{ kind: "weekly_scoped", percent: fable, resets_at: "2030-01-05T10:00:00Z", scope: { model: { display_name: "Fable" } } }],
});
let credentials, usages, calls;
globalThis.fetch = async (url, init) => {
  calls.push([init.method, url, init.headers.Authorization]);
  if (url.endsWith("/credentials")) return { ok: true, json: async () => ({ files: credentials }) };
  const index = JSON.parse(init.body).auth_index;
  const body = usages[index];
  return { ok: true, json: async () => body ? { status_code: 200, body: JSON.stringify(body) } : { status_code: 429, body: "" } };
};
const shape = (accounts) => accounts.map((a) => [a.name, a.active, a.trouble, a.fiveHours?.pct ?? null, a.week.label, a.week.pct]);

// The higher priority account takes new sessions; a fuller Fable week stands for the week.
credentials = [credential("paulius@kodnetas.lt", "p"), credential("paulius.putna@pickitoo.com", "w", { priority: 10 }), credential("codex@x.com", "c", { provider: "codex" })];
usages = { p: usage(12, 30, 3), w: usage(47.4, 25, 52) };
calls = [];
let ask = await fresh();
assert.deepEqual(shape(await ask()), [["kodnetas.lt", false, "", 12, "7d", 30], ["pickitoo.com", true, "", 47, "fable", 52]]);
assert.deepEqual(calls[0], ["GET", "http://papulab.tail0d6b22.ts.net/v8/management/credentials", "Bearer mgmt-key"]);
assert.equal(calls.length, 3);

// Asked again within 3 minutes, the proxy isn't.
await ask();
assert.equal(calls.length, 3);

// A cooling work account hands new sessions to personal; usage it can't get shows as such.
credentials[1].cooldowns = [{ until: "later" }];
usages = { p: usage(12, 30, 3) };
ask = await fresh();
assert.deepEqual(shape(await ask()), [["kodnetas.lt", true, "", 12, "7d", 30], ["pickitoo.com", false, "no usage", null, "7d", 0]]);

// No proxy, no shelf.
globalThis.fetch = async () => { throw new Error("offline"); };
ask = await fresh();
assert.deepEqual(await ask(), []);
TEST
node "$scratch/test.mjs"
echo "herdr-app accounts tests passed: priority picks the account in use, a fuller Fable week stands for the week, the proxy is asked once per 3 minutes, a cooling account steps aside, failed usage and a missing proxy degrade quietly"
