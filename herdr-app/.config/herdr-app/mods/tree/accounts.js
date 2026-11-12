// The Claude accounts behind papulab's CLIProxyAPI at the foot of the sidebar: which one new
// sessions go to, and how much of its 5h and week windows every account has spent.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { home } from "herdr";
import * as fs from "fs/promises";

// Red from here, as sketchybar's item; yellow on the way there.
const WARN_PCT = 70;
const FULL_PCT = 85;
const ICONS = "mods/workspace-chrome";

// The panel too: browsers force https on .dev, so not lab.putna.dev.
const PROXY = "http://papulab.tail0d6b22.ts.net";
// Anthropic throttles its usage endpoint; the tree asks every 30s.
const USAGE_EVERY_MS = 3 * 60000;

let cached = { at: 0, accounts: [] };

// Each proxy account and its usage; [] when the proxy can't be asked.
export async function askAccounts() {
  if (Date.now() - cached.at < USAGE_EVERY_MS) return cached.accounts;
  try {
    const key = (await fs.readFile(`${home()}/.cli-proxy-api/management-key`, "utf8")).trim();
    const credentials = (await management(key, "GET", "/credentials")).files.filter((c) => c.provider === "claude");
    const inUse = nextInLine(credentials);
    const accounts = await Promise.all(credentials.map(async (c) => account(c, c === inUse, await askUsage(key, c))));
    cached = { at: Date.now(), accounts };
  } catch {
    cached = { at: Date.now(), accounts: [] };
  }
  return cached.accounts;
}

// Folded, the account in use alone, on the panel button's line; a click on it shows them all
// under their column heads, and a click on those folds it again.
export function accountsShelf(t, accounts, open, toggle) {
  const inUse = accounts.find((a) => a.active) ?? accounts[0];
  return v_flex().flex_none().border_t(1).border_color(t.border)
    .when(!open, (el) => el.child(foldedRow(t, inUse, toggle)))
    .when(open, (el) => el.child(tableView(t, accounts, toggle)));
}

// The button and name to the left, the numbers and the week's reset to the right, each as wide
// as its text; the sidebar's 16px inset on both sides, less the button's own padding at the left.
function foldedRow(t, a, toggle) {
  return h_flex().id("tree-accounts-folded").h(28).pl(16 - 4.5).pr(16).gap(6).items_center().text_size(12).text_color(t.dim)
    .cursor_pointer().hover((s) => s.bg(t.hover)).on_click(toggle)
    .child(panelButton(t).ml(0))
    .child(accountName(t, a).flex_1().min_w(0))
    .child(h_flex().flex_none().gap(10)
      .child(percent(t, a, a.fiveHours))
      .child(percent(t, a, a.week))
      .child(div().whitespace_nowrap().child(a.week.resetsAt ? resetLabel(a.week.resetsAt) : "")));
}

async function management(key, method, path, body) {
  const res = await fetch(`${PROXY}/v8/management${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

// The proxy calls Anthropic with the account's own token; null when that fails.
async function askUsage(key, credential) {
  const reply = await management(key, "POST", "/requests/api-call", {
    auth_index: credential.auth_index,
    method: "GET",
    url: "https://api.anthropic.com/api/oauth/usage",
    header: { Authorization: "Bearer $TOKEN$", "anthropic-beta": "oauth-2025-04-20" },
  }).catch(() => null);
  return reply?.status_code === 200 ? JSON.parse(reply.body) : null;
}

// Where a new session goes: the highest priority among accounts free to take it.
function nextInLine(credentials) {
  const free = credentials.filter((c) => trouble(c) === "");
  return free.reduce((best, c) => (best === null || priority(c) > priority(best) ? c : best), null);
}

function priority(credential) {
  return Number(credential.priority ?? 0);
}

function trouble(credential) {
  if (credential.disabled) return "off";
  if (credential.quota_blocked) return "blocked";
  if (credential.cooldowns.length > 0) return "cooling";
  return "";
}

// A Fable week fuller than the whole week is the one that stops the account, so it takes the
// week's place.
function account(credential, active, usage) {
  const fable = usage?.limits?.find((l) => l.kind === "weekly_scoped" && l.scope?.model?.display_name === "Fable");
  const windows = [
    usage?.five_hour && { label: "5h", pct: Math.round(usage.five_hour.utilization ?? 0), resetsAt: usage.five_hour.resets_at },
    usage?.seven_day && { label: "7d", pct: Math.round(usage.seven_day.utilization ?? 0), resetsAt: usage.seven_day.resets_at },
    fable && { label: "fable", pct: Math.round(fable.percent ?? 0), resetsAt: fable.resets_at },
  ].filter(Boolean);
  const find = (label) => windows.find((w) => w.label === label) ?? null;
  const weeks = [find("7d"), find("fable")].filter(Boolean);
  return {
    name: accountLabel(credential),
    active,
    trouble: usage === null ? "no usage" : trouble(credential),
    fiveHours: find("5h"),
    week: weeks.reduce((most, w) => (w.pct > most.pct ? w : most), weeks[0] ?? { label: "7d", pct: 0, resetsAt: null }),
  };
}

// An email's domain names the account in less room than the whole address.
function accountLabel(credential) {
  const label = credential.label ?? credential.email ?? credential.name;
  return label.includes("@") ? label.split("@")[1] : label;
}

// Its icon in line with the account names; a click on it doesn't also fold the shelf.
function panelButton(t) {
  return h_flex().id("tree-proxy-panel").size(22).ml(-5).flex_none().rounded(4).items_center().justify_center().cursor_pointer()
    .hover((s) => s.bg(t.input)).tooltip("Open the proxy's panel")
    .on_click((_e, cx) => { cx.stop_propagation(); cx.open_url(`${PROXY}/management.html`); })
    .child(svg(`${ICONS}/terminal.svg`).size(13).text_color(t.dim));
}

// Columns of numbers, the week's reset beside them; a window's own reset on hovering its number.
function tableView(t, accounts, toggle) {
  return v_flex()
    .child(tableColumns(t.dim, h_flex().child(panelButton(t)), "5h", "7d", "").id("tree-accounts-heads").h(24).text_size(11).cursor_pointer().hover((s) => s.bg(t.hover)).on_click(toggle))
    .children(accounts.map((a) => accountRow(t, a, accountName(t, a))));
}

function accountRow(t, a, name) {
  return tableColumns(t.dim, name, percent(t, a, a.fiveHours), percent(t, a, a.week), a.week.resetsAt ? resetLabel(a.week.resetsAt) : "")
    .h(24).text_size(12).when(a.active, (el) => el.bg(t.selected));
}

function tableColumns(color, name, fiveHours, week, resets) {
  return h_flex().px(16).gap(6).items_center().text_color(color)
    .child(name.flex_1().min_w(0))
    .child(div().w(36).flex_none().flex().justify_end().child(fiveHours))
    .child(div().w(36).flex_none().flex().justify_end().child(week))
    .child(div().w(68).flex_none().flex().justify_end().whitespace_nowrap().child(resets));
}

function percent(t, a, w) {
  if (!w) return div().child("–");
  const named = w.label === "fable" ? "f " : "";
  return div().id(`tree-pct-${a.name}-${w.label}`).font_medium().text_color(usageColor(t, w.pct))
    .tooltip(w.resetsAt ? `${w.label} resets ${resetLabel(w.resetsAt)}` : `${w.label}: nothing spent`)
    .child(`${named}${w.pct}%`);
}

function accountName(t, a) {
  return div().truncate().text_color(a.active ? t.accent : t.muted).when(a.active, (d) => d.font_medium())
    .child(a.trouble === "" ? a.name : `${a.name} · ${a.trouble}`);
}

function usageColor(t, pct) {
  return pct >= FULL_PCT ? t.ansi1 : pct >= WARN_PCT ? t.ansi3 : t.ansi2;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// Within a day, how long; else the weekday and hour it resets, in local time. Reset times sit
// a moment off the hour (05:59:59.9), so it's the nearest hour.
function resetLabel(resetsAt) {
  const at = new Date(Date.parse(resetsAt) + 30 * 60000);
  const hours = (at.getTime() - Date.now()) / 3600000;
  if (hours < 24) return `in ${Math.max(1, Math.ceil(hours))}h`;
  return `${WEEKDAYS[at.getDay()]} ${String(at.getHours()).padStart(2, "0")}:00`;
}
